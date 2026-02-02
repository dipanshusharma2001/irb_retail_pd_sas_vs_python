/*============================================================*/
/* Notebook: 02a_feature_engineering_binning_woe.sas                          */
/* Purpose : Feature Engineering, Binning and WOE calculation                */
/*============================================================*/

/*---------------- Include Config & Utilities ----------------*/

%let main_dir = /home/u64435593/sasuser.v94/projects;
%include "&main_dir./sas/src/config.sas";
%include "&main_dir./sas/src/utility_functions.sas";
%put &=main_dir;

data model_df_after_eda;
set process.model_df_after_eda;
run;

proc contents data=model_df_after_eda; run;

*Variables Categorization;
%let id_cols =id t0;
%let target_var = default_flag;
%let num_continuous_vars = loan_amnt int_rate installment annual_inc dti revol_bal revol_util;
%let num_count_vars = delinq_2yrs inq_last_6mths open_acc pub_rec total_acc;
%let categorical_vars = term sub_grade purpose verification_status home_ownership emp_length;


*Binning Strategy and Coarse Classing;

*In retail PD modelling, raw variables are rarely used directly due to skewness, outliers, and unstable risk 
patterns at extreme values. Instead, variables are transformed into ordered risk buckets using coarse classing 
and monotonic binning.

The binning strategy in this notebook follows these principles:
- Preserve economic intuition and monotonic risk ordering
- Use coarse, interpretable bins rather than overly granular splits
- Ensure sufficient observations in each bin
- Handle outliers through capping rather than deletion

All binning decisions are data-driven but constrained by credit risk logic. For numeric continuous variables, 
monotonic binning is performed using isotonic regression to smooth noisy default-rate patterns while preserving 
economic intuition. For numeric count and categorical variables, manual coarse classing is preferred due to 
sparsity and zero inflation, which can lead to unstable isotonic fits.

The Ordinal categorical variables requires perfect monotonicity after clubbing. Such variables are term, grade, 
and sub_grade. There are few semi-ordinal variables, they require directional monotonicity not strict. Such variables 
are emp_length and home_ownership. The Nominal Categorical vaiables are purpose, verification_status. 
Monotonicity is not conceptually required for these variables.;

*categorical Variables;
%categorical_woe(var=term);
%categorical_woe(var=grade);
%categorical_woe(var=sub_grade);
%categorical_woe(var=purpose);
%categorical_woe(var=verification_status);
%categorical_woe(var=home_ownership);
%categorical_woe(var=emp_length);

*
- The loan term variable exhibits clear and monotonic risk differentiation, with 60-month loans showing materially 
  higher default risk than 36-month loans. The variable is retained without further grouping.

- grade/Sub-grade provides additional risk differentiation beyond grade. However, raw sub-grades exhibit local 
  non-monotonicity in higher risk bands due to sparsity. Sub-grades are therefore coarsely grouped within 
  grades to restore monotonic risk ordering (E1, E23, E45, F1, F2, F3, F45, G12345). As Grade and Subgrade 
  are highly correlated, grade can be dropped for future analysis.

- Purpose: Low Risk - [car, credit_card, home improvement], Medium Risk - [debt consolidation, house, wedding], 
  High Risk - [small business, educational, renewable energy], remaining as per conservative behaviour we can 
  assign to high risk.

- Verification status exhibits monotonic WOE behavior, with higher observed risk for verified loans due to 
  risk selection effects. The variable is retained without reordering.

- Home ownership exhibits economically intuitive risk ordering after grouping rare categories. Ownership and 
  mortgage status are associated with lower risk, while renting and non-ownership indicate higher default 
  risk.

- Employment length shows weak and noisy risk patterns at fine granularity. The variable is therefore coarsely 
  grouped, with missing values treated as a separate high-risk category.
 ;
 
*Clubbing Categorical Variables;
data work.model_df_after_eda;
    set work.model_df_after_eda;

    * 1. Clubbed Term (no change, explicit copy);
    clubbed_term = term;

    * 2. Clubbed Sub-Grade;
    if sub_grade in ('E2', 'E3') then clubbed_sub_grade = 'E23';
    else if sub_grade in ('E4', 'E5') then clubbed_sub_grade = 'E45';
    else if sub_grade in ('F4', 'F5') then clubbed_sub_grade = 'F45';
    else if find(sub_grade, 'G') > 0 then clubbed_sub_grade = 'G';
    else clubbed_sub_grade = sub_grade;

    * 3. Clubbed Loan Purpose;
    if purpose in ('car', 'credit_card', 'home_improvement') then
        clubbed_purpose = '0. low_risk';
    else if purpose in ('debt_consolidation', 'house', 'wedding') then
        clubbed_purpose = '1. medium_risk';
    else
        clubbed_purpose = '2. high_risk';

    * 4. Clubbed Verification Status (no change);
    clubbed_verification_status = verification_status;

    * 5. Clubbed Home Ownership;
    if home_ownership in ('OWN', 'MORTGAGE') then
        clubbed_home_ownership = '0. owned';
    else if home_ownership = 'RENT' then
        clubbed_home_ownership = '1. rent';
    else
        clubbed_home_ownership = '2. other';

    * 6. Clubbed Employment Length;
    if emp_length in ('< 1 year', '1 year') then
        clubbed_emp_length = '0. <2_YEARS';
    else if emp_length in ('2 years', '3 years', '4 years', '5 years') then
        clubbed_emp_length = '1. 2_5_YEARS';
    else if emp_length in ('6 years', '7 years', '8 years', '9 years') then
        clubbed_emp_length = '2. 6_9_YEARS';
    else if emp_length = '10+ years' then
        clubbed_emp_length = '3. 10+_YEARS';
    else
        clubbed_emp_length = 'unknown';

run;

%let clubbed_categorical_vars =
    clubbed_term
    clubbed_sub_grade
    clubbed_purpose
    clubbed_verification_status
    clubbed_home_ownership
    clubbed_emp_length;
    
proc freq data=work.model_df_after_eda;
    tables &clubbed_categorical_vars. / missing norow nocol nocum nopercent;
run;

%clubbed_categorical_woe(var=clubbed_term);
%clubbed_categorical_woe(var=clubbed_sub_grade);
%clubbed_categorical_woe(var=clubbed_purpose);
%clubbed_categorical_woe(var=clubbed_verification_status);
%clubbed_categorical_woe(var=clubbed_home_ownership);
%clubbed_categorical_woe(var=clubbed_emp_length);

proc means data=work.model_df_after_eda nmiss;
    var clubbed_term_woe clubbed_sub_grade_woe clubbed_purpose_woe
        clubbed_verification_status_woe clubbed_home_ownership_woe
        clubbed_emp_length_woe

        clubbed_term_iv clubbed_sub_grade_iv clubbed_purpose_iv
        clubbed_verification_status_iv clubbed_home_ownership_iv
        clubbed_emp_length_iv;
run;

* Numerical Count Variables;

*Delinquency 2 years;
data model_df_after_eda;
    set model_df_after_eda;
    length delinq_2yrs_adj $10;

    if missing(delinq_2yrs) then delinq_2yrs_adj = 'missing';
    else if delinq_2yrs = 0 then delinq_2yrs_adj = '0';
    else if delinq_2yrs = 1 then delinq_2yrs_adj = '1';
    else if delinq_2yrs = 2 then delinq_2yrs_adj = '2';
    else delinq_2yrs_adj = '3_PLUS';
run;

%calc_woe(data=model_df_after_eda, feature=delinq_2yrs_adj, target=&target_var., out=out.woe_delinq_2yrs_adj);

ods graphics / reset imagename="woe_delinq_2yrs_adj";
ods listing gpath="&main_dir./sas/summaries_and_charts";
proc sgplot data=out.woe_delinq_2yrs_adj;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="delinq_2yrs_adj";
    title "WOE – delinq_2yrs_adj";
run;

data model_df_after_eda;
    set model_df_after_eda;
    length clubbed_delinq_2yrs $10;

    if delinq_2yrs_adj = 'missing' then clubbed_delinq_2yrs = '0';
    else clubbed_delinq_2yrs = delinq_2yrs_adj;
run;

%calc_woe(data=model_df_after_eda, feature=clubbed_delinq_2yrs, target=&target_var., out=out.woe_clubbed_delinq_2yrs);

ods graphics / reset imagename="woe_clubbed_delinq_2yrs";
ods listing gpath="&main_dir./sas/summaries_and_charts";
proc sgplot data=out.woe_clubbed_delinq_2yrs;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="clubbed_delinq_2yrs";
    title "WOE – clubbed_delinq_2yrs";
run;

proc sql;
    create table model_df_after_eda as
    select
        a.*,
        b.woe as clubbed_delinq_2yrs_woe,
        b.iv  as clubbed_delinq_2yrs_iv
    from model_df_after_eda a
    left join out.woe_clubbed_delinq_2yrs b
        on a.clubbed_delinq_2yrs = b.bin;
quit;


* Enquiries last 6 months;
data model_df_after_eda;
    set model_df_after_eda;
    length inq_last_6mths_adj $10;

    if missing(inq_last_6mths) then inq_last_6mths_adj = 'missing';
    else if inq_last_6mths = 0 then inq_last_6mths_adj = '0';
    else if inq_last_6mths = 1 then inq_last_6mths_adj = '1';
    else if inq_last_6mths = 2 then inq_last_6mths_adj = '2';
    else if inq_last_6mths = 3 then inq_last_6mths_adj = '3';
    else inq_last_6mths_adj = '4_PLUS';

run;

ods graphics / reset imagename="woe_inq_last_6mths_adj";
ods listing gpath="&main_dir./sas/summaries_and_charts";
%calc_woe(data=model_df_after_eda, feature=inq_last_6mths_adj, target=&target_var., out=out.woe_inq_last_6mths_adj);

proc sgplot data=out.woe_inq_last_6mths_adj;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="inq_last_6mths_adj";
    title "WOE – inq_last_6mths_adj";
run;

data model_df_after_eda;
    set model_df_after_eda;
    length clubbed_inq_last_6mths $10;

    if inq_last_6mths_adj = 'missing' then clubbed_inq_last_6mths = '0';
    else clubbed_inq_last_6mths = inq_last_6mths_adj;
run;

%calc_woe(data=model_df_after_eda, feature=clubbed_inq_last_6mths, target=&target_var., out=out.woe_clubbed_inq_last_6mths);
ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_clubbed_inq_last_6mths";

proc sgplot data=out.woe_clubbed_inq_last_6mths;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="clubbed_inq_last_6mths";
    title "WOE – clubbed_inq_last_6mths";
run;

proc sql;
    create table model_df_after_eda as
    select
        a.*,
        b.woe as clubbed_inq_last_6mths_woe,
        b.iv  as clubbed_inq_last_6mths_iv
    from model_df_after_eda a
    left join out.woe_clubbed_inq_last_6mths b
        on a.clubbed_inq_last_6mths = b.bin;
quit;


* public records;
data model_df_after_eda;
    set model_df_after_eda;
    length pub_rec_adj $12;

    if missing(pub_rec) then pub_rec_adj = 'missing';
    else if pub_rec = 0 then pub_rec_adj = '0';
    else if pub_rec = 1 then pub_rec_adj = '1';
    else pub_rec_adj = '2_PLUS';
run;

%calc_woe(data=model_df_after_eda, feature=pub_rec_adj, target=&target_var., out=out.woe_pub_rec_adj);

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_pub_rec";
proc sgplot data=out.woe_pub_rec_adj;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="pub_rec_adj";
    title "WOE – Public Records";
run;

data model_df_after_eda;
    set model_df_after_eda;
    length clubbed_pub_rec $12;

    if pub_rec_adj = 'missing' then clubbed_pub_rec = '0';
    else clubbed_pub_rec = pub_rec_adj;
run;


%calc_woe(data=model_df_after_eda, feature=clubbed_pub_rec, target=&target_var., out=out.woe_clubbed_pub_rec);

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_clubbed_pub_rec";
proc sgplot data=out.woe_clubbed_pub_rec;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="clubbed_pub_rec";
    title "WOE – Public Records (Clubbed)";
run;

proc sql;
    create table model_df_after_eda as
    select
        a.*,
        b.woe as clubbed_pub_rec_woe,
        b.iv  as clubbed_pub_rec_iv
    from model_df_after_eda a
    left join out.woe_clubbed_pub_rec b
        on a.clubbed_pub_rec = b.bin;
quit;


*open accounts;
data model_df_after_eda;
    set model_df_after_eda;
    length open_acc_adj $15;

    if missing(open_acc) then open_acc_adj = '0. missing';
    else if 0 <= open_acc <= 2 then open_acc_adj = '1. 0_2';
    else if 3 <= open_acc <= 5 then open_acc_adj = '2. 3_5';
    else if 6 <= open_acc <= 10 then open_acc_adj = '3. 6_10';
    else if 11 <= open_acc <= 20 then open_acc_adj = '4. 11_20';
    else if 21 <= open_acc <= 30 then open_acc_adj = '5. 21_30';
    else open_acc_adj = '6. 30_PLUS';

run;

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_open_acc_adj";
%calc_woe(data=model_df_after_eda, feature=open_acc_adj, target=&target_var., out=out.woe_open_acc_adj);
proc sgplot data=out.woe_open_acc_adj;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="open_acc" fitpolicy=rotate;
    title "WOE – Open Accounts";
run;

data model_df_after_eda;
    set model_df_after_eda;
	length clubbed_open_acc $15;

    if open_acc_adj = '0. missing' then clubbed_open_acc = '1. 0_2';
    else if open_acc_adj in ('5. 21_30', '6. 30_PLUS') then clubbed_open_acc = '5. 21_PLUS';
    else clubbed_open_acc = open_acc_adj;
run;

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_clubbed_open_acc";
%calc_woe(data=work.model_df_after_eda, feature=clubbed_open_acc, target=&target_var., out=out.woe_clubbed_open_acc);
proc sgplot data=out.woe_clubbed_open_acc;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="clubbed_open_acc" fitpolicy=rotate;
    title "WOE – Open Accounts (Clubbed)";
run;

proc sql;
    create table model_df_after_eda as
    select
        a.*,
        b.woe as clubbed_open_acc_woe,
        b.iv  as clubbed_open_acc_iv
    from model_df_after_eda a
    left join out.woe_clubbed_open_acc b
        on a.clubbed_open_acc = b.bin;
quit;


*total accounts;
data model_df_after_eda;
    set model_df_after_eda;
    length total_acc_adj $15;

    if missing(total_acc) then total_acc_adj = '0. missing';
    else if 0 <= total_acc <= 5 then total_acc_adj = '1. 0_5';
    else if 6 <= total_acc <= 10 then total_acc_adj = '2. 6_10';
    else if 11 <= total_acc <= 20 then total_acc_adj = '3. 11_20';
    else if 21 <= total_acc <= 30 then total_acc_adj = '4. 21_30';
    else if 31 <= total_acc <= 50 then total_acc_adj = '5. 31_50';
    else total_acc_adj = '6. 50_PLUS';
run;

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_total_acc_adj";

%calc_woe(data=model_df_after_eda, feature=total_acc_adj, target=&target_var., out=out.woe_total_acc_adj);

proc sgplot data=out.woe_total_acc_adj;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="total_acc" fitpolicy=rotate;
    title "WOE – Total Accounts";
run;

data model_df_after_eda;
    set model_df_after_eda;
    length clubbed_total_acc $15;

    if total_acc_adj = '0. missing' then clubbed_total_acc = '1. 0_5';
    else clubbed_total_acc = total_acc_adj;
run;

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="woe_clubbed_total_acc";

%calc_woe(data=model_df_after_eda, feature=clubbed_total_acc, target=&target_var., out=out.woe_clubbed_total_acc);

proc sgplot data=out.woe_clubbed_total_acc;
    vbar bin / response=woe datalabel;
    yaxis label="Weight of Evidence" grid;
    xaxis label="clubbed_total_acc" fitpolicy=rotate;
    title "WOE – Total Accounts (Clubbed)";
run;

proc sql;
    create table model_df_after_eda as
    select
        a.*,
        b.woe as clubbed_total_acc_woe,
        b.iv  as clubbed_total_acc_iv
    from model_df_after_eda a
    left join out.woe_clubbed_total_acc b
        on a.clubbed_total_acc = b.bin;
quit;


*Saving the updated dataset;
data process.model_df_after_eda;
set work.model_df_after_eda;
run;


* for numerically continuous variables, new script has been created due to memory issue in SAS on Demand Academics;

