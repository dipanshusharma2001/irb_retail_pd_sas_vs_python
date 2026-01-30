options 
    mprint
    mlogic
    symbolgen
    nodate
    nonumber
    formchar="|----|+|---+=|-/\<>*";


%let main_dir = /Users/sharmadipanshu/Developer/KPMG/irb_retail_pd_sas_vs_python/";

libname raw      "&main_dir./data/raw";
libname processed "&main_dir./sas/data";
libname out      "&main_dir./sas/summaries_and_charts";

options fmtsearch=(work);
