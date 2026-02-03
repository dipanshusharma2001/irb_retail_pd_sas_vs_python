/*============================================================*/
/* Notebook: 01_data_preparation_and_eda.sas                          */
/* Purpose : Data preparation & initial EDA                  */
/*============================================================*/

/*---------------- Include Config & Utilities ----------------*/
%let main_dir = /home/u64435593/sasuser.v94/projects;

%include "&main_dir./sas/src/config.sas";
%include "&main_dir./sas/src/utility_functions.sas";
%put &=main_dir;

proc import datafile="&main_dir./data/raw/mortgage_data_raw.csv"
    out=process.raw_mortgage_data dbms=csv replace;
    guessingrows=max;
run;*2260701,25;

proc contents data=process.raw_mortgage_data; run;

data process.mortgage_base;
    set process.raw_mortgage_data(
        keep=
            &id_cols.
            &loan_contract_cols.
            &borrower_profile_cols.
            loan_status
    );
run;*2260701,25;


*--------------------------------------Portfolio Definition and Basic Filters--------------------------------------;

*checking the duplicates in loan id;
proc sql;
    select
        count(*) as total_obs,
        count(distinct id) as distinct_ids
    from process.mortgage_base;
quit;

proc freq data = process.mortgage_base; tables issue_d/missing norow nocol nocum nopercent; run;

*there are 33 cases where issue date is missing, removing such cases and convering the date to month end date ;
data mortgage_base;
    set process.mortgage_base;
  
    if missing(issue_d) then delete;
    t0 = intnx('month', issue_d, 0, 'end');
    format t0 date9.;
run;*2260668,26;

*The loan_status variable represents the final observed outcome of the loan and is used only to define whether the loan ever defaulted. 
The dataset does not provide sufficient information to determine the exact timing of default within the loan lifecycle.;
proc freq data = mortgage_base; tables loan_status/missing norow nocol nocum nopercent; run; 

* if the loan is charged off or defaulted can be considered as default cases, remaining categories fall under non-defaulted cases;
data process.model_df;
    set mortgage_base;

    if loan_status in (
        'Charged Off',
        'Default',
        'Does not meet the credit policy. Status:Charged Off'
    ) then default_flag = 1;
    else default_flag = 0;
run;


*--------------------------------------Exploratory Data Analysis--------------------------------------;

*Basic checks for modelling datasets
1. Loan id should be unique 
2. Unique values in a feature should be as expected 
3. The values of a feature should be stored as correct data types;

proc contents data = process.model_df; run;

*distribution of defaults across defaulted and non_defalted observations;
proc freq data=process.model_df; tables loan_status * default_flag / norow nocol nocum nopercent; run;

* checking the uniqueness on loan id;
proc sql;
    select
        count(*) as total_obs,
        count(distinct id) as unique_ids,
        (count(*) = count(distinct id)) as id_is_unique
    from process.model_df;
quit;

*number of unique values for each variable;
proc freq data=process.model_df nlevels; tables _all_ / noprint; run;



*--------------------------------------Target and Portfolio Overview-------------------------------------;
*- In this section, we perform high-level exploratory checks to:
    - Understand the overall default rate
    - Verify that default behavior is sensible across key dimensions
    - Ensure the target variable behaves as expected;
    
    
* number of loans are 2260668;

* Default Rate
- Overall Portfolio
- By Loan term 
- By Credit Grade
- By Loan Purpose
- By Income Verification Status
- By Loan amount Deciles;


proc sql;
    create table out.portfolio_summary as 
    select mean(default_flag) format=percent8.2 as overall_pd,
    count(*) as n_loans
    from process.model_df;
quit;

proc sql;
    create table out.def_rate_by_term as 
    select
        term,
        mean(default_flag) format=percent8.2 as default_rate
    from process.model_df
    group by term
    order by term;
quit;

proc sql;
	create table out.def_rate_by_grade as 
    select
        grade,
        mean(default_flag) format=percent8.2 as default_rate
    from process.model_df
    group by grade
    order by grade;
quit;

proc sql;
	create table out.def_rate_by_purpose as
    select
        purpose,
        mean(default_flag) format=percent8.2 as default_rate
    from process.model_df
    group by purpose
    order by default_rate desc;
quit;

proc sql;
	create table out.def_rate_by_verificaion_status as
    select
        verification_status,
        mean(default_flag) format=percent8.2 as default_rate
    from process.model_df
    group by verification_status;
quit;

/* Create loan amount deciles */
proc rank data=process.model_df groups=10 out=work.loan_amt_ranked;
    var loan_amnt;
    ranks loan_amt_decile;
run;

/* Default rate by decile */
proc sql;
	create table out.def_rate_by_loan_amount as
    select
        loan_amt_decile,
        min(loan_amnt) as min_loan_amt format=comma12.,
        max(loan_amnt) as max_loan_amt format=comma12.,
        mean(default_flag) format=percent8.2 as default_rate
    from work.loan_amt_ranked
    group by loan_amt_decile
    order by loan_amt_decile;
quit;


* Missing values across variables;
proc means data=process.model_df nmiss noprint; output out=out._miss_counts nmiss=; run;


*
1. The modelling dataset comprises approximately 2.26 million loan accounts, with an observed portfolio-level default rate of ~11.9% across the full loan lifecycle. 
   This default rate is within a reasonable range for unsecured retail lending and does not indicate any obvious data quality or target construction issues.

2. A clear and intuitive relationship is observed between loan tenor and default risk, with 60-month loans exhibiting materially higher default rates than 36-month loans. 
   This aligns with retail credit risk theory, where longer repayment horizons are associated with greater uncertainty and higher probability of default.

3. Default rates increase monotonically across credit grades from A to G, indicating strong and consistent risk ordering. This behavior confirms the internal coherence of 
   the dataset and supports the use of monotonic transformations (such as binning and WOE) in subsequent modelling steps.

4. Meaningful risk differentiation is also observed across loan purposes, with higher default rates for purposes such as educational and small business loans, and lower default 
   rates for car loans and credit card refinancing. These patterns are economically intuitive and suggest that loan purpose captures relevant underlying risk characteristics.

5. Income verification status exhibits higher default rates for verified loans compared to non-verified loans, reflecting risk selection effects rather than direct risk mitigation. 
   This reinforces the need to interpret such variables carefully during modelling.

Overall, the portfolio demonstrates stable, intuitive risk patterns across key dimensions, providing confidence in the modelling base table and target definition. 
No variables require exclusion at this stage, and the dataset is well-prepared for variable-level diagnostics, binning, and feature transformation in the next step.
;


*-------------------------------------------------------Variable-Level Diagnostics------------------------------------------------------;
*In this section, we examine individual variables to:

	- Understand their distribution
	- Compare behavior between defaulted and non-defaulted loans
	- Identify variables suitable for binning, transformation, or grouping;


* Numerical Variables- Distribution by Default Status;
proc means data=process.model_df n mean std min p25 median p75 max;
    class default_flag;
    var loan_amnt int_rate dti delinq_2yrs inq_last_6mths;
    output out= out.numerical_variable_stats;
run;

*Across key numerical variables, defaulted loans exhibit consistently riskier profiles compared to non-defaulted loans. Defaulted loans have a higher average loan amount 
and a materially higher interest rate, indicating that both exposure size and pricing capture underlying credit risk. Debt-to-income ratios are also higher for defaulted 
loans, with visible right-tail outliers, suggesting the need for capping or binning during variable treatment. Count-based bureau variables such as delinquencies in the 
last two years and recent credit inquiries show higher average values for defaulted loans, despite medians remaining at zero, reflecting highly skewed distributions. 
Overall, these patterns confirm that the numerical variables possess discriminatory power but will require appropriate transformations (binning, capping, or grouping) prior to modelling.;


*Categorical Variables Risk Ordering;

* default rate by home ownership;
proc sql;
	create table out.def_rate_by_home_ownership as 
    select
        home_ownership,
        mean(default_flag) format=percent8.2 as default_rate
    from process.model_df
    group by home_ownership
    order by default_rate desc;
quit;

*default rate by employee length;

/* Create ordered employment length mapping */
data work.emp_len_map;
    length emp_length $20;
    input emp_length $ order;
    datalines;
< 1 year   1
1 year     2
2 years    3
3 years    4
4 years    5
5 years    6
6 years    7
7 years    8
8 years    9
9 years    10
10+ years  11
;
run;

/* Calculate default rate by employment length */
proc sql;
    create table work.pd_by_emp_length as
    select
        a.emp_length,
        b.order,
        mean(a.default_flag) format=percent8.2 as default_rate
    from process.model_df a
    left join work.emp_len_map b
        on a.emp_length = b.emp_length
    group by a.emp_length, b.order;
quit;

/* Display in logical order */
proc sort data=work.pd_by_emp_length out = out.def_rate_emp_length;
    by order;
run;

*Categorical variables demonstrate meaningful and economically intuitive risk ordering. Home ownership status shows clear differentiation, with the highest default rates 
observed for OTHER, NONE, and RENT, while borrowers with MORTGAGE or OWN statuses exhibit lower default risk, consistent with asset-backed stability. Employment length 
displays a broadly declining risk pattern with longer tenure, though the relationship is not strictly monotonic, indicating potential noise across individual categories. 
This suggests that employment length may benefit from coarse grouping rather than fine-grained categorisation. Overall, categorical variables capture structural borrower 
risk and are suitable candidates for grouped encoding or WOE-based transformation.;


*Default Rate Plots;
ods graphics on / MAXOBS=2260668;
ods listing gpath="&main_dir./sas/summaries_and_charts";

ods graphics / reset imagename="default_rate_by_loan_term" imagefmt=png;
proc sgplot data=process.model_df;
    vbar term / response=default_flag stat=mean datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Loan Term";
    title "Default Rate by Loan Term";
    format default_flag percent8.2;
run;

ods graphics / reset imagename="default_rate_by_credit_grade" imagefmt=png;
proc sgplot data=process.model_df;
    vbar grade / response=default_flag stat=mean datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Credit Grade";
    title "Default Rate by Credit Grade";
    format default_flag percent8.2;
run;

ods graphics / reset imagename="default_rate_by_verification_status" imagefmt=png;
proc sgplot data=process.model_df;
    vbar verification_status / response=default_flag stat=mean datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Verification Status";
    title "Default Rate by Verification Status";
    format default_flag percent8.2;
run;

ods graphics / reset imagename="default_rate_by_home_ownership" imagefmt=png;
proc sgplot data=process.model_df;
    vbar home_ownership / response=default_flag stat=mean datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Home Ownership";
    title "Default Rate by Home Ownership";
    format default_flag percent8.2;
run;

ods graphics / reset imagename="default_rate_by_loan_purpose" imagefmt=png;
proc sgplot data=process.model_df;
    vbar purpose / response=default_flag stat=mean datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Loan Purpose" fitpolicy=rotate;
    title "Default Rate by Loan Purpose";
    format default_flag percent8.2;
run;

ods graphics / reset imagename="default_rate_by_loan_amount" imagefmt=png;
proc sgplot data=work.loan_amt_ranked;
    vbar loan_amt_decile / response=default_flag stat=mean datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Loan Amount Decile";
    title "Default Rate by Loan Amount Deciles";
    format default_flag percent8.2;
run;

ods graphics / reset imagename="default_rate_by_emp_length" imagefmt=png;
proc sgplot data=work.pd_by_emp_length;
    vbar emp_length / response=default_rate datalabel;
    yaxis label="Default Rate" grid;
    xaxis label="Employment Length" fitpolicy=rotate;
    title "Default Rate by Employment Length";
run;



*The figure above illustrates default rate variation across key portfolio dimensions. Consistent risk ordering is observed across structural (term, grade), 
borrower (employment length, home ownership), and loan characteristics (purpose, loan size), reinforcing the suitability of these variables for downstream PD modelling.;


*----------------------------------------------------------Variable Treatment Strategy (Post-EDA)----------------------------------------------------------;

*In this section, we formalize variable-level treatment decisions based on exploratory analysis.

Not all variables are analyzed with the same depth at this stage. Instead, we distinguish between:

	- Strong, high-level drivers that were explicitly validated during EDA
	- Bureau / application variables that require transformation before meaningful analysis
	- Variables to be excluded due to redundancy, leakage, or poor suitability for modelling


1. Bureau / Application Variables Deferred for Detailed Analysis

The following bureau and application variables were not subjected to aggressive raw EDA (e.g. fine-grained default-rate plots by raw values). This is intentional.

These variables are typically:
	- Highly skewed
	- Sparse or zero-inflated
	- Noisy at the raw-value level
	- More meaningfully analyzed after binning or grouping

Performing raw EDA on such variables can be misleading due to low counts in tail categories and unstable default rates. These variables will be investigated in detail 
during monotonic binning and WOE analysis. These variables are annual_inc, dti, open_acc, total_acc, revol_bal, revol_util, delinq_2yrs, inq_last_6mths, pub_rec, installment. 
At the EDA stage, we focused instead on high-level structural drivers (e.g. term, grade, purpose) that are easier to reason about and serve as early sanity checks for target validity.


2. Variables Dropped from the Modelling Dataset

	- emp_title: Extremely high cardinality free-text field with limited incremental predictive value and high preprocessing complexity.
	- funded_amnt, funded_amnt_inv: Highly collinear with loan_amnt and reflect funding mechanics rather than borrower credit risk.
	- issue_d: Replaced by a standardized observation date (T0).
	- loan_status: Final loan outcome used only to construct the default flag, retaining it would introduce target leakage.


3. Variable-Level Strategy for Retained Core Variables

- loan_amnt: The loan amount variable shows moderate risk differentiation across the portfolio. It is discrete and widely distributed with no evidence of instability or 
  extreme outliers. This variable will be retained and transformed using monotonic binning. No capping is required.

- int_rate: Interest rate exhibits strong and monotonic separation between defaulted and non-defaulted loans. It will be retained and transformed using ordered binning 
  to preserve monotonic risk behavior.

- term: Loan term shows clear and intuitive risk differentiation, with longer tenors associated with higher default rates. This variable will be retained and treated as a categorical predictor.

- grade / sub_grade: Credit grades demonstrate near-perfect monotonic risk ordering. Sub-grade will be preferred over grade for finer granularity and retained as an ordered categorical variable.

- purpose: Loan purpose shows meaningful but noisy risk differentiation. Low-frequency categories will be grouped, and the variable will be transformed using grouped categorical bins.

- home_ownership: Home ownership exhibits economically intuitive risk ordering. Rare categories will be combined, and the variable will be treated as an ordered categorical predictor.

- emp_length: Employment length shows weak monotonicity and informative missingness. This variable will be retained, coarsely grouped, and missing values treated as a separate category.

- verification_status: Income verification status shows clear risk differentiation, with higher observed default rates for verified loans due to risk selection effects rather than direct 
  risk mitigation. This variable will be retained and treated as a categorical predictor without further transformation beyond grouping, if required.;



*variables to drop based on EDA decisions;
data process.model_df_after_eda;
    set process.model_df(
        drop=
            emp_title
            funded_amnt
            funded_amnt_inv
            issue_d
            loan_status
    );
run;