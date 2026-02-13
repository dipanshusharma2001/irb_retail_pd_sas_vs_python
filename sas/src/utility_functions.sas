%let main_dir = /home/u64435593/sasuser.v94/projects;
%include "&main_dir./sas/src/config.sas";

%let id_cols = id issue_d term;

%let loan_contract_cols = loan_amnt funded_amnt funded_amnt_inv int_rate installment grade sub_grade purpose verification_status;

%let borrower_profile_cols = annual_inc emp_length emp_title home_ownership dti delinq_2yrs inq_last_6mths open_acc pub_rec revol_bal revol_util total_acc;

%let outcome_cols = loan_status last_pymnt_d last_pymnt_amnt total_rec_prncp total_rec_int recoveries collection_recovery_fee;

%let hardship_cols = hardship_flag hardship_dpd hardship_loan_status debt_settlement_flag settlement_status;


/*---------------- WOE Calculation ----------------*/
%macro calc_woe(data=, feature=, target=, out=);

data _woe_input;
    set &data.;
    length _bin $30;

    if vtype(&feature.) = 'N' then
        _bin = strip(put(&feature., best.));
    else
        _bin = strip(&feature.);
run;

proc sql;
    create table _woe_base as
    select
        coalesce(_bin, 'missing') as bin,
        count(*) as pop,
        sum(&target.) as def
    from _woe_input
    group by calculated bin;
quit;


data &out.;
    set _woe_base;
    nondef = pop - def;
run;

proc sql noprint;
    select sum(def), sum(nondef)
    into :tot_def, :tot_nondef
    from &out.;
quit;

data &out.;
    set &out.;
    perc_def    = def / &tot_def.;
    perc_nondef = nondef / &tot_nondef.;
    if perc_def > 0 and perc_nondef > 0 then
        woe = log(perc_nondef / perc_def);
    iv = (perc_nondef - perc_def) * woe;
run;

%mend calc_woe;


/*---------------- PD Scoring ----------------*/
%macro score_pd(data=, out=, intercept=, betas_ds=);

proc sql;
    create table &out. as
    select a.*,
           1 / (1 + exp(-(
               &intercept.
               %do i = 1 %to &sqlobs.;
                   + a.%scan(&&var&i,1) * b.beta
               %end;
           ))) as pd
    from &data. a;
quit;

%mend score_pd;


/*---------------- Model Performance Summary ----------------*/
%macro performance_summary(data=, pd_col=, target=, out_deciles=);

proc rank data=&data. groups=10 out=_ranked;
    var &pd_col.;
    ranks decile;
run;

proc sql;
    create table &out_deciles. as
    select
        decile,
        count(*) as population,
        sum(&target.) as defaults,
        mean(&pd_col.) as avg_pd
    from _ranked
    group by decile
    order by decile;
quit;

data &out_deciles.;
    set &out_deciles.;
    obs_default_rate = defaults / population;
run;

%mend performance_summary;


/*---------------- Stability Index ----------------*/
%macro stability_index(exp=, act=, var=, out=);

proc freq data=&exp. noprint;
    tables &var. / out=_exp_dist;
run;

proc freq data=&act. noprint;
    tables &var. / out=_act_dist;
run;

proc sql;
    create table &out. as
    select
        coalesce(a.&var., b.&var.) as level,
        coalesce(a.percent, 0.0001) / 100 as exp_pct,
        coalesce(b.percent, 0.0001) / 100 as act_pct
    from _exp_dist a
    full join _act_dist b
    on a.&var. = b.&var.;
quit;

data &out.;
    set &out.;
    psi = (act_pct - exp_pct) * log(act_pct / exp_pct);
run;

%mend stability_index;



*macros for feature engineering;
*WOE Calculation for Categorical Variables;

%macro categorical_woe(var=);

    %calc_woe(data=work.model_df_after_eda, feature=&var., target=&target_var., out=work.woe_&var.);
    
    data out.woe_&var.;
        set work.woe_&var.;
    run;

    /*---------------- Plot WOE ----------------*/
   	ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_&var.";

    proc sgplot data=work.woe_&var.;
        vbar bin / response=woe datalabel;
        yaxis label="Weight of Evidence" grid;
        xaxis label="&var."
	    %if &var = purpose or &var = emp_length %then %do;
    	    fitpolicy=rotate
    	%end;;
        title "WOE by &var.";
    run;

%mend categorical_woe;

*WOE Calculation on Categorical Variables after clubbing them;
%macro clubbed_categorical_woe(var=);

    %calc_woe(data=work.model_df_after_eda, feature=&var., target=&target_var., out=work.woe_&var.);
    data out.woe_&var.;
        set work.woe_&var.;
    run;
    
    ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_&var.";

    proc sgplot data=work.woe_&var.;
        vbar bin / response=woe datalabel;
        yaxis label="Weight of Evidence" grid;
        xaxis label="&var."
            %if &var = clubbed_purpose or &var = clubbed_emp_length %then %do;
                fitpolicy=rotate
            %end;;
        title "WOE by &var.";
    run;

    proc sql;
        create table work.model_df_after_eda as
        select
            a.*,
            b.woe as &var._woe,
            b.iv  as &var._iv
        from work.model_df_after_eda a
        left join work.woe_&var. b
            on a.&var. = b.bin;
    quit;

%mend clubbed_categorical_woe;

*WOE for Numerical Continuous Variables;
%macro calc_woe_numeric(data=, feature=, target=, out=);

    data _woe_input2 / view=_woe_input2;
        set &data.;
        length &feature._chr $30;
        &feature._chr = strip(put(&feature., best.));
    run;

    %calc_woe(data=_woe_input2, feature=&feature._chr, target=&target., out=&out.);

    data &out.;
        set &out.;
        bin_num = input(bin, best.);
    run;

%mend calc_woe_numeric;

%macro continuous_woe(var=, bins=, target_var=);
    proc rank
        data=work.model_df_after_eda(where=(not missing(&var.)))
        groups=&bins.
        out=work.&var._ranked(keep=row_id &var._bin_id);
        var &var.;
        ranks &var._bin_id;
    run;

    data work.&var._missing;
        set work.model_df_after_eda(keep=row_id &var.);
        where missing(&var.);
        &var._bin_id = -1;
    run;

    data work.&var._bins;
        set work.&var._ranked work.&var._missing;
    run;

    proc sql;
        create table work.model_df_after_eda as
        select
            a.*,
            b.&var._bin_id
        from work.model_df_after_eda a
        left join work.&var._bins b
            on a.row_id = b.row_id;
    quit;

    ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_&var.";

    %calc_woe_numeric(data=work.model_df_after_eda, feature=&var._bin_id, target=&target_var., out=out.woe_&var.);

    proc sgplot data=out.woe_&var.;
        vbar bin_num / response=woe datalabel;
        yaxis label="Weight of Evidence" grid;
        xaxis label="&var._bin_id";
        title "WOE – &var.";
    run;

    proc sql;
    create table work.model_df_after_eda as
    select
        a.*,
        b.woe as &var._woe
    from work.model_df_after_eda a
    left join out.woe_&var. b
        on a.&var._bin_id = b.bin_num;
	quit;
	
%mend continuous_woe;


%macro continuous_woe_clubbed(var=, target_var=);

    ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_clubbed_&var.";
    %calc_woe(data=work.model_df_after_eda, feature=&var._bin_id_adj, target=&target_var., out=out.woe_clubbed_&var.);

    proc sgplot data=out.woe_clubbed_&var.;
        vbar bin / response=woe datalabel;
        yaxis label="Weight of Evidence" grid;
        xaxis label="&var._bin_id_adj";
        title "WOE – Clubbed &var.";
    run;
    
    proc sql;
    create table work.model_df_after_eda as
    select
        a.*,
        b.woe as &var._woe2
    from work.model_df_after_eda a
    left join out.woe_clubbed_&var. b
        on strip(put(a.&var._bin_id_adj, 30.)) = b.bin;
	quit;

%mend continuous_woe_clubbed;


*Single Factor Analysis;
%macro sfa_single(var=);

    /*---------------- Logistic Regression ----------------*/
    ods exclude all;
    ods output ParameterEstimates = _pe Association = _assoc;
    proc logistic data=data_after_woe descending;
        model default_flag = &var.;
    run;
    
    ods select all;

    /*---------------- coefficients, p_value, auc, gini---------*/
    proc sql;
    	select put(Estimate, best32.), put(ProbChiSq, best32.)
    	into :coef trimmed, :pval trimmed from _pe
    	where Variable = "&var.";
    quit;
  
    proc sql; select nValue2 into :gini from _assoc where Label2 = "Somers' D"; quit;

    %let sign_coef = %sysevalf(%sysfunc(sign(&coef.)));

    /*---------------- Correlation ----------------*/
    ods exclude all;
    ods output PearsonCorr = _corr;

    proc corr data=data_after_woe pearson; var &var.; with default_flag; run;
    
    ods select all;
    proc sql; select &var. into :corr from _corr where variable = "default_flag"; quit;

    %let sign_corr = %sysevalf(%sysfunc(sign(&corr.)));

    /*---------------- Append results ----------------*/
    data _sfa_row;
    length variable $50;
    variable    = "&var.";
    coefficient = &coef.;
    p_value     = &pval.;
    sign        = &sign_coef.;
    gini        = &gini.;
    corr        = &corr.;
    sign_corr   = &sign_corr.;
	run;

	proc append base=work.sfa_results data=_sfa_row force;
run;


%mend sfa_single;

%macro run_sfa(varlist);

    %local i var n;
    %let n = %sysfunc(countw(&varlist.));

    %do i = 1 %to &n.;
        %let var = %scan(&varlist., &i.);
        %sfa_single(var=&var.);
    %end;

%mend run_sfa;



*Multi Factor Ananalysis;

data work.economic_driver_map;
    length variable $20 economic_driver $20;

    /* credit quality */
    variable='subgr_w'; economic_driver='credit_quality'; output;
    variable='rate_w';  economic_driver='credit_quality'; output;

    /* behavioural */
    variable='delinq_w'; economic_driver='behavioural'; output;
    variable='inq_w';    economic_driver='behavioural'; output;
    variable='pubrec_w'; economic_driver='behavioural'; output;
    variable='open_w';   economic_driver='behavioural'; output;
    variable='totacc_w'; economic_driver='behavioural'; output;
    variable='rutil_w';  economic_driver='behavioural'; output;
    variable='rbal_w';   economic_driver='behavioural'; output;

    /* affordability */
    variable='inc_w';  economic_driver='affordability'; output;
    variable='dti_w';  economic_driver='affordability'; output;
    variable='inst_w'; economic_driver='affordability'; output;

    /* exposure */
    variable='loan_w'; economic_driver='exposure'; output;
    variable='term_w'; economic_driver='exposure'; output;

    /* customer profile */
    variable='home_w'; economic_driver='customer_profile'; output;
    variable='empl_w'; economic_driver='customer_profile'; output;
    variable='ver_w';  economic_driver='customer_profile'; output;
    variable='purp_w'; economic_driver='customer_profile'; output;
run;


%macro run_mfa(combo=, model_id=);

    %let varlist = &combo.;

    /* Logistic */
    ods exclude all;
    ods output ParameterEstimates=_pe Association=_assoc;
    proc logistic data=data_after_woe descending;
        model default_flag = &varlist.;
        output out=_pred p=prob;
    run;
    
    *gini, vif, percentage contrbution;
    ods select all;
    proc sql; select nValue2 into :gini from _assoc where Label2 = "Somers' D"; quit;

    ods exclude all;
    ods output ParameterEstimates=_vif;
    proc reg data=data_after_woe;
        model default_flag = &varlist. / vif;
    run;
    quit;
    
    ods select all;
    proc means data=data_after_woe ; var &varlist.; output out=_std std=; run;
    proc transpose data=_std out=_std_long(rename=(col1=std)); var &varlist.; run;
    
    *Cleaning coefficient and vif dataset;
    data _coef;
        set _pe(rename=(Variable=variable Estimate=coefficient ProbChiSq=p_value));
        if variable ne "Intercept";
        gini = &gini.;
    run;

    data _vif2;
        set _vif(rename=(Variable=variable VarianceInflation=vif));
    run;

    proc sql;
        create table _result as
        select &model_id. as model_id,
        	   a.variable,
               a.coefficient,
               a.p_value,
               b.vif,
               c.std,
               abs(a.coefficient * c.std) as abs_contrib,
               a.gini,
               d.economic_driver
        from _coef a
        left join _vif2 b
            on a.variable = b.variable
        left join _std_long c
            on a.variable = c._NAME_
        left join work.economic_driver_map d
            on a.variable = d.variable;
    quit;

    proc append base=work.mfa_results data=_result force;
    run;

%mend;



