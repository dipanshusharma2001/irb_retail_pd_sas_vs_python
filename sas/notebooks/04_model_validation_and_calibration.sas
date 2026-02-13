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

