/*============================================================*/
/* Notebook: 02_feature_engineering_binning_woe.sas                          */
/* Purpose : Feature Engineering, Binning and WOE calculation                */
/*============================================================*/

/*---------------- Include Config & Utilities ----------------*/
%include "&main_dir./sas/src/config.sas";
%include "&main_dir./sas/src/utility_functions.sas";
%put &=main_dir;

data model_df_after_eda;
set process.model_df_after_eda;
run;

proc contents data=model_df_after_eda; run;