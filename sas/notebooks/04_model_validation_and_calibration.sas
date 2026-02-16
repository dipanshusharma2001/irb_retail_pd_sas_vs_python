/*============================================================*/
/* Notebook: 04_model_validation_and_calibration.sas                          */
/* Purpose : This notebook evaluates the robustness, stability, and calibration of the 
   developed PD model. While the model specification and coefficients were finalised using 
   the full development universe, this notebook assesses whether the frozen model behaves 
   consistently across different data slices, thereby validating its suitability for deployment and regulatory use. */
/*============================================================*/

/*---------------- Include Config & Utilities ----------------*/

%let main_dir = /home/u64435593/sasuser.v94/projects;
%include "&main_dir./sas/src/config.sas";
%include "&main_dir./sas/src/utility_functions.sas";
%put &=main_dir;

data scored_data;
set process.model_scored;
year = year(t0);
run;

proc contents data=scored_data; run;


*final selected model;
data out.final_selected_model;
set out.mfa_results;
if model_id = 22;
run;

* there is no intercept in it, lets run the logistic again to populate intercept for future scoring;
proc logistic data=scored_data descending;
    model default_flag = dti_w home_w inc_w inq_w subgr_w ver_w;
    ods output ParameterEstimates=final_pe;
run;

proc sql noprint; select Estimate into :intercept from final_pe where Variable = "Intercept"; quit;
data betas;
    set final_pe;
    where Variable ne "Intercept";
    keep Variable Estimate;
    rename Variable=variable Estimate=coefficient;
run;

/* ================================= Calibration and Validation Sample (OOT) ============================== */

*
Given the snapshot nature of the available dataset, the model was developed using the full sample to ensure robust variable 
selection and stable coefficient estimation. Since the recent dataset is not available, the validation exercise conducted in t
his notebook represents a pseudo out-of-time (OOT) analysis, rather than a fully independent holdout validation. The purpose of 
this pseudo-OOT analysis is not to re-assess model specification, but to evaluate the stability, rank-order preservation, and 
calibration behaviour of the frozen model across different time slices. This approach is consistent with industry practice when 
true OOT samples are not available and is intended to demonstrate key elements of the IRB model development and validation lifecycle.;

proc freq data=scored_data; tables t0 year / missing norow nocol nocum nopercent; run;

*yearwise default rate;
proc sql;
    create table work.yearwise_default_rate as
    select 
        year,
        count(*) as population,
        sum(default_flag) as defaults,
        mean(default_flag) as default_rate
    from scored_data
    group by year
    order by year;
quit;

data out.yearwise_default_rate;
    set work.yearwise_default_rate;
    by year;
    five_year_lradr = mean(
        lag4(default_rate),
        lag3(default_rate),
        lag2(default_rate),
        lag1(default_rate),
        default_rate
    );
run;

*overall default rate;
proc sql noprint; select mean(default_rate) into :lradr from out.yearwise_default_rate; quit;

data _null_; lradr = &lradr; put "LRADR 2007-2018: " lradr percent8.4; run;

*
The available dataset spans loan vintages from June 2007 to December 2018, with a material increase in portfolio size and data 
completeness from 2012 onwards. Earlier vintages (2007–2010) exhibit relatively low observation counts and are heavily influenced 
by the global financial crisis, making them less representative of the current risk profile of the portfolio. Consequently, for the 
purpose of calibration and validation, the analysis focuses on the more recent and statistically robust period starting from 2013, 
where annual observations exceed 130,000 accounts and default behaviour stabilises.

In line with industry practice and supervisory expectations for IRB models, a five-year window (2013–2017) is selected as the calibration 
sample to estimate the Long-Run Average Default Rate (LRADR) and perform portfolio-level PD alignment. This period provides sufficient 
depth to smooth short-term volatility while remaining representative of recent credit conditions. The 2018 vintage, comprising 
approximately 495,000 observations, is designated as the out-of-time (OOT) validation sample. Although the model was developed using the 
full snapshot of data, this split enables a pseudo-OOT assessment of rank-order stability, calibration behaviour, and score distribution 
consistency across time, thereby supporting the evaluation of model robustness and fitness for use;

*LRADR Trend;
ods graphics / reset imagename="5_yearwise_default_rate_trend";
ods listing gpath="&main_dir./sas/summaries_and_charts";

proc sgplot data=out.yearwise_default_rate;
    series x=year y=default_rate / markers;
    series x=year y=five_year_lradr / markers;
    yaxis label="Default Rate";
    title "Year-wise Default Rate & 5-Year LRADR";
run;

data calib_data oot_data;
    set scored_data;
    if 2013 <= year <= 2017 then output calib_data;
    else if year = 2018 then output oot_data;
run;

*LRADR and Calibration;
proc sql noprint;
    select variable, coefficient
    into :var1-:var999, :beta1-:beta999
    from betas;

    %let nvars = &sqlobs;
quit;

%apply_frozen_model(input_ds=calib_data, output_ds=calib_data_scored);
%apply_frozen_model(input_ds=oot_data,   output_ds=oot_data_scored);

proc means data=calib_data_scored n mean std min p25 median p75 max; var pd_raw; run;
proc means data=oot_data_scored n mean std min p25 median p75 max; var pd_raw; run;

* Yearly Default rate and LRADR;
proc sql;
    create table calib_yearly_dr as
    select 
        year,
        mean(default_flag) as yearly_dr
    from calib_data_scored
    group by year
    order by year;
quit;

proc sql; select mean(yearly_dr) into :LRADR from calib_yearly_dr; quit;
proc sql; select mean(pd_raw) into :avg_pd_calib from calib_data_scored; quit;

* 
Calibration is performed by adjusting only the intercept of the model so that the average predicted probability of default aligns with the Long-Run Average Default Rate (LRADR). 
The calibration shift (Δ) is defined as the difference between the long-run log-odds of default and the model-implied log-odds of default, i.e., 

															Δ = log(LRADR / (1 - LRADR)) − log(P̄D / (1 - P̄D)),

where P̄D represents the average predicted PD over the calibration window. Economically, Δ captures whether the model is under- or over-predicting risk. If Δ > 0, the model 
under-predicts risk and predicted PDs are shifted upward, if Δ < 0, the model over-predicts risk and PDs are shifted downward.

Importantly, this is an intercept-only calibration approach. The slope coefficients remain unchanged, preserving the rank ordering of borrowers and the marginal 
effects of risk drivers. This approach is consistent with regulatory expectations under the IRB framework, where calibration aligns the portfolio-level average PD 
with observed long-run default experience without altering discriminatory power.
;

data _null_;
    LRADR  = &LRADR;
    avg_pd = &avg_pd_calib;

    delta = log(LRADR / (1 - LRADR)) 
          - log(avg_pd / (1 - avg_pd));

    call symputx("delta", delta);

    put "--------------------------------------";
    put "Intercept Shift (Delta): " delta 12.6;
    put "--------------------------------------";
run;

data calib_data_scored;
    set calib_data_scored;

    logit_raw = log(pd_raw / (1 - pd_raw));
    pd_calibrated = 1 / (1 + exp(-(logit_raw + &delta)));
run;

data oot_data_scored;
    set oot_data_scored;

    logit_raw = log(pd_raw / (1 - pd_raw));
    pd_calibrated = 1 / (1 + exp(-(logit_raw + &delta)));
run;

proc sql; select mean(pd_calibrated) into :avg_pd_calibrated from calib_data_scored; quit;

data _null_;
    avg_pd_cal = &avg_pd_calibrated;
    lradr_val  = &LRADR;

    put "--------------------------------------";
    put "Post-calibration average PD (Calibration sample): " avg_pd_cal percent8.4;
    put "LRADR: " lradr_val percent8.4;
    put "--------------------------------------";
run;

*
The PD model is calibrated using an intercept-only adjustment to align portfolio-level predicted default rates with the Long-Run Average Default Rate (LRADR), estimated over 
the 2013–2017 calibration window. The LRADR for this period is 15.12%, representing a stable long-run estimate of portfolio credit risk after smoothing cyclical fluctuations.

Following the application of the calibrated intercept, the average predicted PD on the calibration sample increases from 12.44% (pre-calibration) to 14.93% (post-calibration), 
bringing the model outputs into close alignment with the LRADR. The residual difference of approximately 19 basis points is economically immaterial and arises due to the 
non-linear transformation between log-odds and probability space, as well as differences between population-weighted PD averages and time-averaged default rates.

Importantly, the calibration is performed through an intercept-only shift, leaving all slope coefficients unchanged. As a result, the model’s rank-ordering, relative risk 
differentiation, and discriminatory power are fully preserved. This calibration approach is consistent with IRB modelling principles and ensures portfolio-level PD alignment 
while maintaining model stability and interpretability.;

*Sample Performance;

** Calibration;

%performance_summary(
    input_ds=calib_data_scored,
    pd_var=pd_calibrated,
    target_var=default_flag,
    bins=10,
    prefix=calib
);

%performance_summary(
    input_ds=oot_data_scored,
    pd_var=pd_calibrated,
    target_var=default_flag,
    bins=10,
    prefix=oot
);











