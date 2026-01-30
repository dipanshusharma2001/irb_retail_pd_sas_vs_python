options 
    mprint
    mlogic
    symbolgen
    nodate
    nonumber
    formchar="|----|+|---+=|-/\<>*";

%let main_dir = /home/u64435593/sasuser.v94/projects;

libname raw      "&main_dir./data/raw";
libname process "&main_dir./sas/data";
libname out      "&main_dir./sas/summaries_and_charts";

options fmtsearch=(work);