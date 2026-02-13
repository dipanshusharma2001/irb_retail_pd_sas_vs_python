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


* Due to larger names of variables, SAS is not able to handle them correctly, fixing the issue here;
data data_after_woe;
    set data_after_woe;

    rename
        clubbed_term_woe                 = term_w
        clubbed_sub_grade_woe            = subgr_w
        clubbed_purpose_woe              = purp_w
        clubbed_verification_status_woe  = ver_w
        clubbed_home_ownership_woe       = home_w
        clubbed_emp_length_woe           = empl_w

        loan_amnt_woe     = loan_w
        int_rate_woe      = rate_w
        installment_woe   = inst_w
        annual_inc_woe    = inc_w
        dti_woe           = dti_w
        revol_bal_woe     = rbal_w
        revol_util_woe    = rutil_w

        clubbed_delinq_2yrs_woe      = delinq_w
        clubbed_inq_last_6mths_woe   = inq_w
        clubbed_open_acc_woe         = open_w
        clubbed_pub_rec_woe          = pubrec_w
        clubbed_total_acc_woe        = totacc_w
    ;
run;

%let cat_vars = term_w subgr_w purp_w ver_w home_w empl_w;
%let cont_vars = loan_w rate_w inst_w inc_w dti_w rbal_w rutil_w;
%let count_vars = delinq_w inq_w open_w pubrec_w totacc_w;
%let final_var_list = &cat_vars. &cont_vars. &count_vars.;


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

%run_sfa(&final_var_list.);

proc sort data=work.sfa_results out= out.sfa_results;
    by p_value descending gini;
run;


*
- Single Factor Analysis (SFA) was conducted using WOE-transformed predictors. All candidate variables exhibit intuitive sign behaviour, with negative correlation between WOE and 
  default flag, indicating that higher WOE values are consistently associated with lower default risk.

- Univariate discriminatory power, measured using Gini, is meaningful across all variables, with the strongest predictors being credit quality and pricing-related variables 
  such as sub-grade, interest rate, verification status, and recent inquiry behaviour. Even the weakest variables demonstrate Gini values above 2%, indicating non-trivial 
  standalone predictive power.

Overall, no variable fails SFA on sign logic or lack of explanatory power. All variables are therefore retained for further evaluation in the multivariate modelling stage.;

ods output PearsonCorr = work._corr_matrix;
proc corr data=data_after_woe noprob out= out.sfa_correlation_matrix; var &final_var_list.; run;

data work.corr_abs;
    set work._corr_matrix;
    array nums _numeric_;
    do i = 1 to dim(nums);
        nums[i] = abs(nums[i]);
    end;
    drop i;
run;

proc sort data=work.corr_abs; by variable; run;
proc transpose data=work.corr_abs out=work.corr_long(rename=(col1=correlation)); by variable; run;

data work.high_corr_pairs;
    set work.corr_long;
    where correlation > 0.6 and variable ne _NAME_;
    if variable < _NAME_;
run;

proc print data=work.high_corr_pairs;
    title "Highly Correlated Variable Pairs (|corr| > 0.6)";
run;

ods listing gpath="&main_dir./sas/summaries_and_charts";
ods graphics / reset imagename="sfa_selected_correlation_heatmap";
proc sgplot data=work.corr_long;
    heatmapparm 
        x=variable 
        y=_NAME_ 
        colorresponse=correlation;
    gradlegend;
    title "Correlation Matrix Heatmap (Absolute)";
run;


*A correlation analysis shows that the majority of variable pairs exhibit low to moderate correlations, indicating that the feature engineering process has 
 successfully reduced redundant information.

Three variable pairs exhibit relatively high correlation (above 60%):

- Sub-grade and interest rate, reflecting the direct linkage between borrower credit quality and loan pricing
- Open accounts and total accounts, both capturing dimensions of borrower credit depth
- Loan amount and installment amount, where installment is mechanically derived from loan amount and term

These relationships are economically intuitive and expected in retail credit portfolios. No variables are removed at this stage, as correlation analysis 
serves as a diagnostic rather than a selection criterion. Potential multicollinearity will be explicitly addressed during multi-factor analysis (MFA) 
through coefficient stability checks and variance inflation factor (VIF) assessment. Variables forming highly correlated pairs will not be simultaneously 
retained in the final model.;



*------------------------Multi Factor Analysis---------------------------------;

* 
After completing Single Factor Analysis (SFA), correlation screening, and economic driver classification, an extensive Multi-Factor Analysis (MFA) was 
performed in Python to identify stable and economically meaningful variable combinations. All possible 4-variable combinations were first evaluated 
after applying exclusion rules (removing highly correlated pairs) and category constraints (ensuring balanced numerical and categorical representation). 
Logistic regression was run for each valid combination, and performance was assessed using Gini (2*AUC – 1). Survivor frequency analysis was then conducted 
to identify variables that consistently appeared in high-performing models.

Building on the strongest survivors, combinations of size 5, 6, 7, and 8 were subsequently evaluated in Python. For each combination, we computed model Gini, 
coefficient signs, p-values, VIF, and contribution percentages. The final selected model was chosen based on a combination of statistical strength 
(high Gini, significant coefficients), stability (low multicollinearity), correct economic sign behaviour, and balanced driver representation. This exhaustive 
combinatorial search ensured robust model selection before transitioning to SAS.

Re-running the full combinatorial search in SAS would require executing tens of thousands of logistic regressions, which is computationally expensive and 
unnecessary given that the exhaustive search has already been completed and validated in Python. Therefore, for execution efficiency and reproducibility, we do not 
repeat the full search in SAS. Instead, we restrict the SAS evaluation to combinations of size 4 to 6 drawn from the final shortlisted candidate set.;

%let final_candidate_vars = inc_w inq_w subgr_w ver_w home_w dti_w;

data work.mfa_results;
    length model_id 8. variable $20 economic_driver $30;
    format coefficient p_value vif std abs_contrib gini 12.6;
    stop;
run;

* TODO: figure out the proc iml error, grid search implemented using do loop for now, will fix the iml later.;
/* proc iml; */
/*     varNames = {"inc_w" "inq_w" "subgr_w" "ver_w" "home_w" "dti_w"}; */
/*     n = ncol(varNames); */
/*     model_id = .; */
/*     combo = ""; */
/*      */
/*     create work.combinations var {"model_id" "combo"}; */
/*     char combo $ 200; /* Define the length of the character variable */
/*     id = 0; */
/*      */
/*     do k = 4 to 6; */
/*         combIdx = allcomb(n, k); */
/*          */
/*         do i = 1 to nrow(combIdx); */
/*             id = id + 1; */
/*             model_id = id; */
/*             comboVars = varNames[combIdx[i,]]; */
/*             combo = comboVars[1]; */
/*             do j = 2 to k; */
/*                 combo = trim(combo) || " " || trim(comboVars[j]); */
/*             end; */
/*             append; */
/*         end; */
/*     end; */
/*     close work.combinations; */
/* quit; */


data work.combinations;
    length combo $200 model_id 8;
    array vars[6] $32 _temporary_
        ("inc_w" "inq_w" "subgr_w" "ver_w" "home_w" "dti_w");

    model_id = 0;
    /* k = 4 */
    do i1 = 1 to 3;
        do i2 = i1+1 to 4;
            do i3 = i2+1 to 5;
                do i4 = i3+1 to 6;
                    model_id + 1;
                    combo = catx(" ", vars[i1], vars[i2], vars[i3], vars[i4]);
                    output;
                end;
            end;
        end;
    end;

    /* k = 5 */
    do i1 = 1 to 2;
        do i2 = i1+1 to 3;
            do i3 = i2+1 to 4;
                do i4 = i3+1 to 5;
                    do i5 = i4+1 to 6;
                        model_id + 1;
                        combo = catx(" ", vars[i1], vars[i2], vars[i3], vars[i4], vars[i5]);
                        output;
                    end;
                end;
            end;
        end;
    end;
    /* k = 6 */
    model_id + 1;
    combo = catx(" ", of vars[*]);
    output;
    drop i1-i6;
run;

data _null_;
    set work.combinations;
    call execute(
        '%run_mfa(combo=' || strip(combo) ||
        ', model_id=' || strip(put(model_id,8.)) || ');'
    );
run;

proc sort data= work.mfa_results out= out.mfa_results;
by gini;
run;

* combination 22 performs the best, similar to what we have observed in python. 

The selected six variables jointly achieve:

- Strong discriminatory power (Gini ≈ 40.7%),
- Statistical robustness (all coefficients significant at <1%),
- Low multicollinearity (all VIFs ≈ 1.0–1.2),
- Stable and intuitive contribution structure, avoiding over-concentration in a single driver.

The final model captures diverse and complementary risk dimensions, ensuring no single economic theme dominates the scorecard.

-- clubbed_sub_grade_woe
	--- Primary credit quality indicator
	--- Largest contributor (~56%), reflecting underwriting risk differentiation

-- clubbed_verification_status_woe
	--- ustomer profile / documentation strength
	---Captures selection effects and information asymmetry

-- clubbed_inq_last_6mths_woe
	--- Recent behavioural stress indicator
	--- Adds incremental risk sensitivity beyond static profile variables

-- annual_inc_woe
	--- Affordability / repayment capacity
	--- Stabilises credit quality dominance

-- clubbed_home_ownership_woe
	--- Socio-economic stability proxy
	--- Lowers volatility and improves interpretability

-- dti_woe
	--- Leverage stress measure`
	--- Complements income by capturing obligations burden;

*In Sample Summary Statistics;

data out.final_selected_model;
set out.mfa_results;
if model_id = 22;
run;

*final gini, auc and KS statistic;
proc sql noprint;
    select distinct gini into :final_gini
    from out.mfa_results
    where model_id = 22;
quit;

%let final_auc = %sysevalf((&final_gini + 1)/2);

%put NOTE: Final Model Gini = %sysevalf(&final_gini*100, floor).%;
%put NOTE: Final Model AUC  = %sysevalf(&final_auc*100, floor).%;


* scoring the dataset with finally selected model;
proc logistic data=data_after_woe descending;
    model default_flag = inc_w inq_w subgr_w ver_w home_w dti_w;
    output out=work.model_scored p=pd_hat;
run;

* Decile Summary - movement of observed default rate and pd across bins;
proc rank data=work.model_scored
          groups=10
          descending
          out=work.model_scored;
    var pd_hat;
    ranks decile;
run;

data process.model_scored;
    set work.model_scored;
    decile = decile + 1;
run;

proc sql;
    create table work.decile_summary as
    select 
        decile,
        count(*) as population,
        sum(default_flag) as defaults,
        mean(pd_hat) as avg_pd
    from process.model_scored
    group by decile
    order by decile;
quit;

data work.decile_summary;
    set work.decile_summary;
    obs_default_rate = defaults / population;
run;


data work.decile_summary;
    set work.decile_summary;
    goods = population - defaults;
run;

proc sql noprint;
    select sum(goods), sum(defaults)
    into :total_goods, :total_bads
    from work.decile_summary;
quit;

data out.decile_summary;
    set work.decile_summary;

    retain cum_good cum_bad 0;

    cum_good + goods;
    cum_bad  + defaults;

    cum_good_pct = cum_good / &total_goods.;
    cum_bad_pct  = cum_bad  / &total_bads.;

    ks = abs(cum_bad_pct - cum_good_pct);
run;

proc sql;
    select max(ks) as KS_Statistic format=8.4
    from work.decile_summary;
quit;

ods graphics / reset imagename="decile_summary_final_model";
ods listing gpath="&main_dir./sas/summaries_and_charts";

proc sgplot data=work.decile_summary;
    vbarparm category=decile response=obs_default_rate /
        datalabel
        fillattrs=(color=lightblue);

    series x=decile y=avg_pd /
        markers
        lineattrs=(color=orange thickness=2);

    yaxis label="Rate";
    xaxis label="Decile";
    title "Decile-wise Observed Default Rate vs Average Predicted PD";
run;


*
- The final six-factor PD model demonstrates strong discriminatory power and stable risk ranking across the portfolio. The model achieves an AUC of 
  70.34% and a corresponding Gini coefficient of 40.68%. These results confirm that the selected variable set provides meaningful separation between 
  defaulting and non-defaulting accounts while maintaining economic interpretability and modelling discipline.

- Decile analysis further validates the robustness of the model. Observed default rates increase monotonically across all ten score deciles, ranging from 
  approximately 2% in the lowest-risk decile to nearly 29% in the highest-risk decile. The average predicted PD closely tracks observed default behaviour 
  at each decile level, indicating strong relative calibration even prior to formal calibration adjustments. This confirms that the model effectively ranks 
  borrowers by risk and is suitable for downstream applications such as risk segmentation and policy cut-offs.

- The KS statistic of ~29% indicates good separation between cumulative good and bad distributions. While marginal improvements in Gini are observed when 
  additional variables are introduced, these gains are economically insignificant relative to the added complexity. The six-factor specification therefore 
  represents an optimal balance between predictive power, stability, and interpretability, making it well-suited for regulatory and production use.


Key Takeaways

-- Strong discriminatory power (Gini ≈ 41%) with stable rank ordering
-- Monotonic increase in observed default rates across score deciles
-- Predicted PDs closely aligned with observed behaviour
-- No evidence of overfitting or unstable segmentation
-- Model is fit for calibration and validation in subsequent steps;









































