%let main_dir = /home/u64435593/sasuser.v94/projects;
%include "&main_dir./sas/src/config.sas";

%let id_cols = id issue_d term;

%let loan_contract_cols = loan_amnt funded_amnt funded_amnt_inv int_rate installment grade sub_grade purpose verification_status;

%let borrower_profile_cols = annual_inc emp_length emp_title home_ownership dti delinq_2yrs inq_last_6mths open_acc pub_rec revol_bal revol_util total_acc;

%let outcome_cols = loan_status last_pymnt_d last_pymnt_amnt total_rec_prncp total_rec_int recoveries collection_recovery_fee;

%let hardship_cols = hardship_flag hardship_dpd hardship_loan_status debt_settlement_flag settlement_status;


/*---------------- WOE Calculation ----------------*/
%macro calc_woe(data=, feature=, target=, out=);

proc sql;
    create table _woe_base as
    select
        coalesce(put(&feature., $50.), 'missing') as bin,
        count(*) as pop,
        sum(&target.) as def
    from &data.
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

*WOE Function for Numerical Variables;
%macro calc_woe_numeric(data=, feature=, target=, out=);

    data _woe_input;
        set &data.;
        length &feature._chr $50;
        &feature._chr = strip(put(&feature., best.));
    run;

    %calc_woe(data=_woe_input, feature=&feature._chr, target=&target., out=&out.);

    data &out.;
        set &out.;
        bin_num = input(bin, best.);
    run;

%mend calc_woe_numeric;


* WOE for Numerical Continuous Variables;
%macro continuous_woe(var=, bins=);

    data work.&var._missing work.&var._not_missing;
        set work.model_df_after_eda;

        if missing(&var.) then do;
            &var._bin_id = -1;
            output work.&var._missing;
        end;
        else output work.&var._not_missing;
    run;

    proc rank data=work.&var._not_missing groups=&bins. out=work.&var._ranked;
        var &var.;
        ranks &var._bin_id;
    run;

    data work.model_df_after_eda; set work.&var._missing work.&var._ranked; run;

    ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_&var.";
    %calc_woe_numeric(data=work.model_df_after_eda, feature=&var._bin_id, target=&target_var., out=out.woe_&var.);

    proc sgplot data=out.woe_&var.;
        vbar bin / response=woe datalabel;
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


%macro continuous_woe_clubbed(var=);

    ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_clubbed_&var.";
    %calc_woe_numeric(data=work.model_df_after_eda, feature=&var._bin_id_adj, target=&target_var., out=out.woe_clubbed_&var.);

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
        b.woe as &var._woe
    from work.model_df_after_eda a
    left join out.woe_clubbed_&var. b
        on a.&var._bin_id_adj = b.bin_num;
	quit;

%mend continuous_woe;