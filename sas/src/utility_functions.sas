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