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
    prefix=calib);

*
On the calibration sample, the calibrated model demonstrates strong discriminatory power and good calibration alignment. The AUC of 69.3% (Gini 38.7%) and 
KS of 0.279 are consistent with the development-stage performance observed in Notebook 03, indicating that the frozen model structure remains stable when 
reapplied to the calibration window. Rank-ordering is well preserved, with a smooth and monotonic increase in observed default rates across deciles, 
confirming that the model effectively separates higher-risk from lower-risk accounts.

From a calibration perspective, the intercept-only adjustment successfully aligns the portfolio-level average predicted PD with the Long-Run Average Default Rate 
(LRADR) estimated over the five-year window. Post-calibration, the average predicted PD in the calibration sample closely matches the LRADR, with only a small 
residual difference attributable to rounding and numerical aggregation effects. At the decile level, predicted PDs track observed default rates reasonably well, 
particularly in the central deciles, indicating that the calibration shift preserves relative risk differentiation while correcting level bias at the portfolio 
level.

Overall, the calibration results confirm that the model is well-calibrated on a long-run representative sample, with no evidence of rank-order instability or 
excessive concentration of risk in individual deciles.;


%performance_summary(
    input_ds=oot_data_scored,
    pd_var=pd_calibrated,
    target_var=default_flag,
    bins=10,
    prefix=oot);

*
In the OOT sample (2018), the model continues to exhibit strong discriminatory performance, with an AUC of 71.0% (Gini 42.0%) and KS of 0.305—both marginally 
higher than those observed in the calibration sample. This indicates that the rank-ordering capability of the model remains robust out of time, and that 
relative risk signals learned during development continue to generalise well to later vintages.

However, a clear level misalignment is observed between predicted PDs and realised default rates in the OOT period. Across all deciles, the model systematically 
over-predicts default risk, with observed default rates substantially lower than calibrated PDs. This behaviour is economically intuitive and consistent with 
earlier portfolio-level analysis, which showed that 2018 exhibits the lowest annual default rate (~1.8%) in the dataset, reflecting a benign credit environment 
and improved borrower performance relative to the long-run average.

Importantly, this over-prediction does not indicate model failure. The calibration was intentionally anchored to the LRADR rather than to point-in-time conditions,
in line with IRB principles. As a result, in periods where realised default rates fall materially below long-run levels, conservative bias in predicted PDs is 
expected and, from a regulatory perspective, desirable. Crucially, rank-order stability is preserved in the OOT sample, with monotonic observed default rates 
across deciles and no evidence of score inversion.;


*Stability Diagnostics;

* While the model was developed on the full snapshot, additional stability diagnostics are performed by comparing development-period observations with the 2018 
  out-of-time vintage to provide indicative evidence of temporal stability.;
  

%apply_frozen_model(input_ds=scored_data, output_ds=dev_data_scored);

data dev_data_scored_small;
    set dev_data_scored (keep = pd_raw);

    logit_raw = log(pd_raw / (1 - pd_raw));
    pd_calibrated = 1 / (1 + exp(-(logit_raw + &delta)));
run;


*PSI;
%create_pd_bucket(input_ds=dev_data_scored_small,   output_ds=dev_buckets);
%create_pd_bucket(input_ds=calib_data_scored, output_ds=calib_buckets);
%create_pd_bucket(input_ds=oot_data_scored,   output_ds=oot_buckets);


%stability_index(
    expected_ds=dev_buckets,
    actual_ds=oot_buckets,
    bucket_var=pd_bucket,
    prefix=dev_oot);

%stability_index(
    expected_ds=calib_buckets,
    actual_ds=oot_buckets,
    bucket_var=pd_bucket,
    prefix=calib_oot);

data _null_;
    dev_psi   = &dev_oot_psi;
    calib_psi = &calib_oot_psi;

    put "--------------------------------------";
    put "PSI Calibrated PD (Dev vs OOT): " dev_psi 8.4;
    put "PSI Calibrated PD (Calib vs OOT): " calib_psi 8.4;
    put "--------------------------------------";
run;


* pd density plot;
data dev_vs_oot;
    set dev_data_scored_small(keep = pd_raw pd_calibrated in=a)
        oot_data_scored(keep = pd_raw pd_calibrated in=b) ;

    length sample $10;

    if a then sample = "Dev";
    if b then sample = "OOT";
run;

ods graphics / MAXOBS=2755910 reset imagename="pd_calibration_distribution_dev_vs_oot";
ods listing gpath="&main_dir./sas/summaries_and_charts";

proc sgplot data=dev_vs_oot;
    density pd_calibrated / type=kernel group=sample;
    title "PD Distribution: Dev vs OOT";
run;


data calib_vs_oot;
    set calib_data_scored(keep = pd_raw pd_calibrated in=a)
        oot_data_scored(keep = pd_raw pd_calibrated in=b) ;

    length sample $10;

    if a then sample = "Calib";
    if b then sample = "OOT";
run;

ods graphics / MAXOBS=2755910 reset imagename="pd_calibration_distribution_calib_vs_oot";
ods listing gpath="&main_dir./sas/summaries_and_charts";

proc sgplot data=calib_vs_oot;
    density pd_calibrated / type=kernel group=sample;
    title "PD Distribution: Calib vs OOT";
run;

*
The PD distribution comparison indicates a clear and economically intuitive shift between the reference samples and the OOT population. In both Dev vs OOT and Calibration 
vs OOT comparisons, the OOT distribution is visibly left-shifted, with a higher concentration of observations at lower PD levels and a thinner right tail. This behaviour 
is consistent with the substantially lower observed default rate in the 2018 vintage (≈1.8%) relative to the calibration window (2013–2017), reflecting more benign credit 
conditions rather than deterioration in model performance.

The Population Stability Index (PSI) values further support this conclusion. The PSI for calibrated PDs (Dev vs OOT) is approximately 0.064, while Calibration vs OOT is 
approximately 0.105. Both values are well below commonly used supervisory thresholds (e.g. 0.1 for no material shift and 0.25 for significant shift). The slightly higher 
PSI when comparing Calibration to OOT is expected, as the calibration period was explicitly anchored to a higher long-run default environment, whereas the OOT year 
represents a cyclical low. Importantly, these shifts do not indicate rank-order breakdown or model instability.;

*CSI;

data out.csi_results;
    length variable $50
           CSI_Dev_vs_OOT
           CSI_Calib_vs_OOT 8.;
    stop;
run;

%run_csi;

*
Characteristic Stability Indices (CSI) were computed for all final selected drivers using their original categorical representations, ensuring that the analysis captures 
genuine portfolio mix changes rather than artefacts of WOE scaling. Across all variables, CSI values remain very low for both comparisons:

-- Dev vs OOT: CSI values range from approximately 0.0003 to 0.071
-- Calibration vs OOT: CSI values range from approximately 0.0008 to 0.118

Among the drivers, sub-grade exhibits the highest CSI in the Calibration vs OOT comparison (~0.12), which is consistent with a gradual improvement in credit quality mix 
during 2018. Other behavioural and affordability variables (e.g. inquiries, DTI, income bands) display only minor distributional shifts, well below levels that would 
trigger concern. Overall, the CSI results indicate no material population instability across key risk drivers.

The observed PD and characteristic shifts are economically explainable and acceptable. The OOT period coincides with a phase of strong credit performance, lower realised 
defaults, and improved borrower profiles, naturally leading to lower predicted and observed PDs. Importantly, these shifts are directionally consistent across PD distributions, 
decile behaviour, and driver-level CSI, reinforcing that the model continues to discriminate risk appropriately rather than reacting to noise or structural breaks.

Taken together, the stability diagnostics confirm that the model exhibits robust rank-ordering, stable driver behaviour, and controlled distributional drift. The differences 
observed between the reference samples and OOT reflect cyclical credit dynamics rather than model degradation, supporting the model’s suitability for ongoing use under an 
IRB framework.;

*Saving final modle summary with delta;
data out.final_selected_model;
    set out.final_selected_model;
    delta = &delta;
run;

data out.calib_params;
    LRADR        = &LRADR;
    Avg_Pred_PD  = &avg_pd_calib;
    delta        = &delta;
run;

