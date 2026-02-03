/*============================================================*/
/* Notebook: 03_pd_model_development.sas                          */
/* Purpose : Single Factor Analysis, Multi Factor Analysis, Correlation Analysis  */
/*============================================================*/

/*---------------- Include Config & Utilities ----------------*/

%let main_dir = /home/u64435593/sasuser.v94/projects;
%include "&main_dir./sas/src/config.sas";
%include "&main_dir./sas/src/utility_functions.sas";
%put &=main_dir;

data data_after_woe;
set process.model_df_after_eda;
run;

proc contents data=data_after_woe; run;

*defining the variable lists;
*categorical variables;
%let clubbed_categorical_vars = clubbed_term_woe clubbed_sub_grade_woe clubbed_purpose_woe 
                                clubbed_verification_status_woe clubbed_home_ownership_woe clubbed_emp_length_woe;

*numerical continuous variables;
%let num_continuous_vars = loan_amnt_woe int_rate_woe installment_woe annual_inc_woe dti_woe revol_bal_woe revol_util_woe;

*numerical count variables;
%let num_count_vars = clubbed_delinq_2yrs_woe clubbed_inq_last_6mths_woe clubbed_open_acc_woe clubbed_pub_rec_woe clubbed_total_acc_woe;

%let final_var_list = &clubbed_categorical_vars. &num_continuous_vars. &num_count_vars.;

proc means data=data_after_woe n nmiss;
    var &final_var_list.;
run;

*Single Factor Analysis;
*
- The PD model is developed using a structured Single Factor Analysis (SFA) and Multi-Factor Analysis (MFA) framework. 
  In SFA, each candidate WOE-transformed variable is evaluated individually for sign logic, statistical relevance, and 
  economic intuition. Variables failing these checks are excluded.

- Variables that pass SFA are then evaluated jointly through MFA, starting with a parsimonious core model and gradually 
  expanding model size. The final model is selected based on stability, interpretability, and marginal contribution, rather 
  than purely statistical metrics.;
 
 
data work.sfa_results;
    length variable $50 coefficient p_value sign gini corr sign_corr 8.;
run;

%macro sfa_single(var=);

    /*---------------- Logistic Regression ----------------*/
    ods exclude all;
    ods output ParameterEstimates = _pe
               Association        = _assoc;

    proc logistic data=data_after_woe descending;
        model default_flag = &var.;
    run;
    ods select all;

    /*---------------- Extract coef & p-value ----------------*/
    proc sql noprint;
        select Estimate, ProbChiSq
        into :coef, :pval
        from _pe
        where Variable = "&var.";
    quit;

    /*---------------- Extract AUC (c-statistic) ----------------*/
    proc sql noprint;
        select nValue2
        into :auc
        from _assoc
        where Label2 = "c";
    quit;

    %let gini = %sysevalf(2*&auc. - 1);
    %let sign_coef = %sysevalf(%sysfunc(sign(&coef.)));

    /*---------------- Correlation ----------------*/
    ods exclude all;
    ods output PearsonCorr = _corr;

    proc corr data=data_after_woe pearson;
        var &var.;
        with default_flag;
    run;
    ods select all;

    proc sql noprint;
        select &var.
        into :corr
        from _corr
        where _NAME_ = "default_flag";
    quit;

    %let sign_corr = %sysevalf(%sysfunc(sign(&corr.)));

    /*---------------- Append results ----------------*/
    data work.sfa_results;
        set work.sfa_results
            work.sfa_results
            (obs=0);
        variable    = "&var.";
        coefficient = &coef.;
        p_value     = &pval.;
        sign        = &sign_coef.;
        gini        = &gini.;
        corr        = &corr.;
        sign_corr   = &sign_corr.;
    run;

%mend sfa_single;

%sfa_single(var=clubbed_term_woe)

%macro run_sfa(varlist);

    %local i var n;
    %let n = %sysfunc(countw(&varlist.));

    %do i = 1 %to &n.;
        %let var = %scan(&varlist., &i.);
        %sfa_single(var=&var.);
    %end;

%mend run_sfa;


%run_sfa(&final_var_list.);

proc sort data=work.sfa_results out= out.sfa_results;
    by p_value descending gini;
run;


