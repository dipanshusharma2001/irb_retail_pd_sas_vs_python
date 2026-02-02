%macro continuous_woe_safe(var=);

    /*--------------------------------------------------------*/
    /* Step 1: Create bin ids (NO overwrite of base table)    */
    /*--------------------------------------------------------*/

    /* Separate non-missing */
    proc rank
        data=work.model_df_after_eda(where=(not missing(&var.)))
        groups=10
        out=work.&var._ranked(keep=_n_ &var._bin_id);
        var &var.;
        ranks &var._bin_id;
    run;

    /* Missing bin = -1 */
    data work.&var._missing;
        set work.model_df_after_eda(keep=_n_);
        where missing(&var.);
        &var._bin_id = -1;
    run;

    /* Combine bins (SMALL table) */
    data work.&var._bins;
        set work.&var._ranked work.&var._missing;
    run;

    /*--------------------------------------------------------*/
    /* Step 2: Create VIEW for WOE input (ZERO I/O COPY)      */
    /*--------------------------------------------------------*/
    data work._woe_input / view=work._woe_input;
        merge work.model_df_after_eda
              work.&var._bins;
        by _n_;
        length &var._bin_id_chr $50;
        &var._bin_id_chr = strip(put(&var._bin_id, best.));
    run;

    /*--------------------------------------------------------*/
    /* Step 3: WOE calculation (existing macro, unchanged)   */
    /*--------------------------------------------------------*/
    ods listing gpath="&main_dir./sas/summaries_and_charts";
    ods graphics / reset imagename="woe_&var.";

    %calc_woe(
        data=work._woe_input,
        feature=&var._bin_id_chr,
        target=&target_var.,
        out=out.woe_&var.
    );

    /*--------------------------------------------------------*/
    /* Step 4: Convert bin back to numeric                    */
    /*--------------------------------------------------------*/
    data out.woe_&var.;
        set out.woe_&var.;
        bin_num = input(bin, best.);
    run;

    /*--------------------------------------------------------*/
    /* Step 5: WOE Plot                                       */
    /*--------------------------------------------------------*/
    proc sgplot data=out.woe_&var.;
        vbar bin_num / response=woe datalabel;
        yaxis label="Weight of Evidence" grid;
        xaxis label="&var._bin_id";
        title "WOE – &var.";
    run;

%mend continuous_woe_safe;
