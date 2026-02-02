/*============================================================*/
/* Notebook: 02b_feature_engineering_binning_woe.sas                          */
/* Purpose : Feature Engineering, Binning and WOE calculation                */
/*============================================================*/

/*---------------- Include Config & Utilities ----------------*/

%let main_dir = /home/u64435593/sasuser.v94/projects;
%include "&main_dir./sas/src/config.sas";
%include "&main_dir./sas/src/utility_functions.sas";
%put &=main_dir;

data work.model_df_after_eda;
set process.model_df_after_eda;
run;

proc contents data=model_df_after_eda; run;


*Numerical Continuous Variables;
*Raw continuous variables are not used directly in the PD model, as their relationship with default risk is 
non-linear and unstable across the full range. Variables are therefore transformed using monotonic binning 
and WOE to ensure linearity in the log-odds, stability, and interpretability. Numeric continuous variables 
are first transformed using isotonic regression to learn a monotonic relationship with default risk. The 
isotonic output is then discretised into ordered risk bands, which are subsequently transformed using WOE.;


%continuous_woe(var=loan_amnt, bins=5);
%continuous_woe(var=int_rate, bins=9);
%continuous_woe(var=installment, bins=5);
%continuous_woe(var=annual_inc, bins=9);
%continuous_woe(var=dti, bins=9);
%continuous_woe(var=revol_bal, bins=3);
%continuous_woe(var=revol_util, bins=10);


*Missing values for continuous variables are merged with the nearest economically consistent risk band, based 
on observed default behaviour and credit logic, rather than treated as standalone categories.

Variable	     Missing merged with
- dti	          Lowest risk bin
- annual_inc	  Highest income (lowest risk) bin
- revol_util	  Lowest utilisation risk bin;


data work.model_df_after_eda;
    set work.model_df_after_eda;

    if dti_bin_id = -1 then dti_bin_id_adj = 0;
    else dti_bin_id_adj = dti_bin_id;
    
    if annual_inc_bin_id = -1 then annual_inc_bin_id_adj = 8;
    else annual_inc_bin_id_adj = annual_inc_bin_id;
    
    if revol_util_bin_id = -1 then revol_util_bin_id_adj = 0;
    else revol_util_bin_id_adj = revol_util_bin_id;
run;


%continuous_woe(var=dti);


















