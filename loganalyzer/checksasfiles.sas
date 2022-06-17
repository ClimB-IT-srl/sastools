/* retrieve all the logs in the specified directory                           */
%macro checklogs(loc=,       /* location of where the files are stored            */ 
                 loc2=,      /* location of where report is stored (optional)     */ 
                 ext=.log,   /* filename extension                                */ 
                 fnm=,       /* which types of files to look at (optional)        */
                             /* e.g., Tables – t_, Figures – f_, Listings – l_    */
                             /* separate types of files by delimiter indicated in */
                             /* the delm macro parameter (e.g., t_@f_)            */ 
                 delm=@,     /* delimiter used to separate types of files (opt'l) */ 
                 out=        /* report name (optional)                            */
                 );
                 
%let startdate=%sysfunc(today());

/* need to determine the environment in which this is executed   */
/* syntax for some commands vary from environment to environment */
/* end macro call if environment not Windows or Linux/Unix       */
%if &sysscp = WIN %then %do;
    %let ppcmd = %str(dir);
    %let slash = \;
%end;
%else %if &sysscp = LIN X64 %then %do;
    %let ppcmd = %str(ls -l);
    %let slash = /;
%end;
%else %do;
    %put ENVIRONMENT NOT SPECIFIED;
    abort abend;
%end;

%if "&ext." = "" %then %do;
    %let ext=.log;
%end;

/* if a filename is specified then build the where clause */
%if "&fnm." ne "" %then %do;
    data _null_;
         length fullwhr $2000.; 
         retain fullwhr;

         /* read in each log file and check for undesired messages */
         %let f = 1;
         %let typ = %scan(&fnm., &f., "&delm.");

         /* loop through each type of filename to build the where clause */
         /* embed &typ in double quotes in case filename has any special */
         /* characters or spaces                                         */
         %do %while ("&typ." ne "");

             partwhr = catt("index(flog, '", "&typ.", "')"); 
             fullwhr = catx(" or ", fullwhr, partwhr);

             call symputx('fullwhr', fullwhr);

             %let f = %eval(&f. + 1);
             %let typ = %scan(&fnm., &f., "&delm.");
         %end;
        
    run;
%end;

/* need to build pipe directory statement as a macro var  */
/* because the statement requires a series of single and  */
/* double quotes - by building the directory statement    */
/* this allows the user to determine the directory rather */
/* than it being hardcoded into the program               */
/* macro var will be of the form:'dir "directory path" '  */ 
data _null_;
     libnm = "&loc.";
     dirnm = catx(" ", "'", "&ppcmd.", quote(libnm), " /s'"); 
     call symputx('dirnm', dirnm);
run;

/* read in the contents of the directory containing the logs */ 
filename pdir pipe &dirnm. lrecl=32727;

data logs; 
     infile pdir truncover scanover;
     input filename $char1000.; 
     length flog $100 fdat ftim $10;
     /* keep only the logs */
     if index(filename, "&ext.");
    
     /* count the number of tokens (i.e., different parts of filename) */
     /* if there are no spaces then there should be 5 tokens for WIN   */
     /* or 9 tokens for LIN X64  */
     numtok = countw(filename,' ','q');
    
     /* need to build the flog value based on number of tokens  */
     /* if there are spaces in the log name then need to grab   */
     /* each piece of the log name                              */
     /* the first token that is retrieved will have '.log' and  */
     /* it needs to be removed by substituting a blank          */
     /* also need to parse out the date and time these are in   */
     /* specific spots within the filename so aren't based on   */
     /* number of tokens but will have different locations      */
     /* depending on environment - so parsing of each piece of  */
     /* information will be environment dependent               */
     /* note on the scan function a negative # scans from right */
     /* and a positive # scans from the left                    */
    
     /*********** WINDOWS ENVIRONMENT ************/
     /* the pipe will read in the information in */
     /* the format of: date time am/pm size file */
     /* e.g. 08/24/2015 09:08 PM 18,498 ae.log   */
     /*  '08/24/2015' is first token from left   */
     /*  'ae.log' is first token from right      */
     %if &sysscp. = WIN %then %do;
         flog = tranwrd(scan(filename, -1, " "), "&ext.", ""); 
         ftim = scan(filename, 2, " "); 
         fdat = put(input(scan(filename, 1, " "), ddmmyy10.), date9.);
         if "&ext." ^= ".log" or input(scan(filename, 1, " "), ddmmyy10.) = &startdate.;
     %end;
    
     /***************************** UNIX ENVIRONMENT ******************************/
     /* the pipe will read in the information in the format of: permissions, user, */
     /* system environment, file size, month, day, year or time, filename          */
     /* e.g. -rw-rw-r-- 1 userid sysenviron 42,341 Oct 22 2015 ad_adaapasi.log     */
     /*  '-rw-rw-r--' is first token from left                                     */
     /*  'ad_adaapasi.log' is first token from right                               */
     %else %if &sysscp = LIN X64 %then %do; 
         do j = 9 to numtok;
            tlog = tranwrd(scan(filename, 8 - j, " "), "&ext.", ""); 
            flog = catx(" ", tlog, flog);
         end;
         _ftim = scan(filename, 8, " ");
    
         /* in Unix if year is current year then time stamp is displayed  */
         /* otherwise the year last modified is displayed                 */
         /* so if no year is provided then default to today's year and if */
         /* no time is provided indicated 'N/A'                           */ 
         if anypunct(_ftim) then do;
            ftim = put(input(_ftim, time5.), timeampm8.); 
            yr = put(year(today()), Z4.);
         end; 
         else do;
            ftim = 'N/A'; 
            yr = _ftim;
         end;
    
         fdat = cats(scan(filename, 7, " "), upcase(scan(filename, 6, " ")), yr);
     %end;
run;

/* create a list of logs, dates, times and store in macro variables */ 
proc sql noprint;
     select flog,
            fdat, 
            ftim
     into : currlogs separated by "&delm.",
          : currdats separated by " ",
          : currtims separated by "@"
     from logs
     %if "&fnm." ne "" %then where &fullwhr.;  ; /* need to keep extra semicolon */ 
quit;

%put &=currlogs.;

/* need to make sure the alllogs data set does not exist before getting into loop */ 
proc datasets;
     delete alllogs; 
quit;

/* read in each log file and check for undesired messages */
%let x = 1;
%let lg = %scan(&currlogs., &x., "&delm.");
%let dt = %scan(&currdats., &x.);
%let tm = %scan(&currtims., &x., '@');

/* loop through each log in the directory and look for undesirable messages  */
/* embed &lg in double quotes in case filename has special characters/spaces */
%do %while ("&lg." ne "");
    /* check the log file isn't currently in use */
    %let rc = %sysfunc(filename(fileref, &loc.&slash.&lg.&ext.));
    %let fid = %sysfunc(fopen(&fileref.));
    %if &fid. > 0 %then %do;
        /* file can be opened, so close it to have it available for current process */
        %let rc=%sysfunc(fclose(&fid.));

        /* read the log file into a SAS data set to parse the text */
        data logck&x.;
             infile "&loc.&slash.&lg.&ext." missover pad; 
             input line $1000.;
            
             /* keep only the records that had an undesirable message */ 
             if index(upcase(line), "GETKEY") or 
                index(upcase(line), "SYMBOLGEN") or 
                index(upcase(line), "MPRINT ") or 
                index(upcase(line), " MPRINT") or 
                index(upcase(line), "PW=") or
                index(upcase(line), "PWD=") or
                index(upcase(line), "PASSWORD=") or
                index(upcase(line), "USER=") or
                index(upcase(line), "PW =") or
                index(upcase(line), "PWD =") or
                index(upcase(line), "PASSWORD =") or
                index(upcase(line), "USER =") or
                index(line, "kQLMEaUo8+7ErBOsE1wvcwHxkUo5js4VK1iK1rVSpCw=") or 
                index(line, "10.72.128.33") or
                index(upcase(line), "MLOGIC");
            
             /* create variables that will contain the log that is being scanned */
             /* as well as the and date and time that the log file was created   */ 
             length lognm $100. logdt logtm $10.;
             lognm = upcase("&loc.&slash.&lg.&ext."); 
             logdt = "&dt.";
             logtm = "&tm.";
        run;
    
        /* because there are sometimes issues with SAS certificate */
        /* there will be warnings in the logs that are expected    */
        /* these need to be removed                                */
        data logck&x._2; 
             set logck&x.;
             if index(upcase(line), 'UNABLE TO COPY SASUSER') or 
                index(upcase(line), 'BASE PRODUCT PRODUCT') or 
                index(upcase(line), 'EXPIRE WITHIN') or 
                (index(upcase(line), 'BASE SAS SOFTWARE') and index(upcase(line), 'EXPIRING SOON')) or 
                index(upcase(line), 'UPCOMING EXPIRATION') or 
                index(upcase(line), 'SCHEDULED TO EXPIRE') or
                index(upcase(line), 'SETINIT TO OBTAIN MORE INFO') 
             then delete;
        run;
    
        /* determine the number of undesired messages were in the log */ 
        data _null_;
             if 0 then set logck&x._2 nobs=final;
             call symputx('numobs', left(put(final, 8.))); 
         run;
        
        /* if there is no undesired messages in log create a dummy record for report */
        %if &numobs. = 0 %then %do; 
            data logck&x._2;
                 length lognm $100. line $1000. logdt logtm $10.; 
                 line = "No undesired messages. Log is clean."; 
                 lognm = upcase("&loc.&slash.&lg.&ext.");
                 logdt = "&dt."; 
                 logtm = "&tm.";
                 output; 
            run;
        %end;
    
        /* append all the results into one data set */
        %if &x. = 1 %then %do; 
            data alllogs;
                 set logck&x._2;
            run;
        %end;
        %else %do;
            proc append base=alllogs new=logck&x._2;
            run;
        %end;
    
    %end;
    %let x = %eval(&x. + 1);
    %let lg = %scan(&currlogs., &x., "&delm.");
    %let dt = %scan(&currdats., &x.);
    %let tm = %scan(&currtims., &x., '@');
%end;

/* since a list of files can be provided then the files may not be in order */
proc sort data=alllogs presorted;
     by lognm line;
run;

/* if the name of the output file is not specified then default to the name */
%if "&out." = "" %then %do;
    %let out=all_checklogs;
%end;

/* if the name of the output file is not specified then default to the name */
%if "&loc2." = "" %then %do; 
    data _null_;
         call symputx("loc2", "&loc.");
    run;
%end;

/* create the report */ 
ods listing close;
options orientation=landscape;

ods rtf file="&loc2.&slash.&out..rtf";

title "&loc.";

proc report data=alllogs ls=140 ps=43 spacing=1 missing nowindows headline; 
     column lognm logdt logtm line;
     define lognm / order   style(column)=[width=15%]      "File Name"; 
     define logdt / display style(column)=[width=15%]      "File Date"; 
     define logtm / display style(column)=[width=15%]      "File Time"; 
     define line  / display style(column)=[width=55%] flow "File Message";
     /* force a blank line after each file */ 
     compute after lognm;
         line " "; 
     endcomp;
run;

title;

ods rtf close; 
ods listing;
%mend checklogs;

%let n=0;
%macro readCatalog(path, localpath);
    * this macro reads a directory content, including files and subfolders;
    * it adds all children to zip archive, keeping track of subfolder intermediates;
    %local rc _path filrf did noe filename fid i;

    %if &localpath. = %then
        %let _path = &path.;
    %else 
        %let _path = &path.\&localpath.;
        
    %checklogs(loc=&_path., loc2=F:\Software\ConfigAPP\Lev3\SASAppETL\BatchServer\Logs, ext=.sas, fnm=, delm=@, out=checklogs&n.);

    %let n = %eval(&n. + 1);
    %let filrf = DIR&n.;

    %let rc = %sysfunc(filename(filrf, &_path.));
    %let did = %sysfunc(dopen(&filrf.));
    
    %if &did. le 0 %then %goto exit;
    
    %let noe = %sysfunc(dnum(&did.));

    %do i = 1 %to &noe.;
        %let filename = %bquote(%sysfunc(dread(&did., &i.)));
        %let fid = %sysfunc(mopen(&did., &filename.));
        %if &fid. > 0 %then %do;
            %* do nothing;
        %end;
        %else %do;
            %if &localpath. = %then
                %readCatalog(&path., &filename.);
             %else 
                %readCatalog(&path., &localpath.\&filename.);
        %end;
    %end;
    %let rc=%sysfunc(dclose(&did.));
    
    %exit:
    
%mend readCatalog;

*%checklogs(loc=F:\Software\ConfigAPP\Lev3\SASAppETL\BatchServer\Logs, loc2=, ext=.log, fnm=, delm=@, out=);
*%readCatalog(F:\Software\ConfigAPP\Lev3\SASAppETL\SASEnvironment\SASCode);
%readCatalog(F:\Software\ConfigAPP\Lev3\SASAppETL\SASEnvironment\SASMacro);


