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

data final_selected_model;
set out.final_selected_model;
run;

proc contents data=scored_data; run;

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
consistency across time, thereby supporting the evaluation of model robustness and fitness for use.;



;
