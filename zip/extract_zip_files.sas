options nomprint nomlogic nosymbolgen;
%let move_dir = ~/monrepos/import/CAISSE/;

%macro makedir(destination);
    %let dlm = /;
    %let count = %sysfunc(countc("&destination.", "&dlm.")) - 2;;
    
    %let destination = &destination.&dlm.;

    %let level = &move_dir.;
    
    %do i = 1 %to %eval(&count. + 1);
        %let word = %scan(&destination., &i., &dlm.);
        %let lnew = &level.&word.&dlm.;
        %put &=lnew. - &=word.;
        data _null_;
             rc = filename('newdir',"&lnew.");
             dc = dopen('newdir');
             if dc = 0 then new = dcreate("&word.","&level.");
        run;
        %let level = &lnew.;
    %end;
%mend makedir;

%macro listzipcontents(targdir=, outlist=);
    filename targdir "&targdir.";

    data work._zipfiles;
         length fid 8;
         fid = dopen('targdir');

         if fid = 0 then stop;
         memcount = dnum(fid);

         do i = 1 to memcount;
            memname = dread(fid,i);
            if (reverse(lowcase(trim(memname))) =: 'piz.') OR
               (reverse(lowcase(trim(memname))) =: 'zg.') then
               output;
         end;

         rc = dclose(fid);
    run;

    filename targdir clear;

    proc sql noprint;
         select memname into: zname1- from _zipfiles;
         %let zipcount = &sqlobs.;
    quit;

    %do i = 1 %to &zipcount.;
        %put &targdir./&&zname&i..;
        filename targzip ZIP "&targdir./&&zname&i..";

        data work._contents&i.(keep = zip memname);
             length zip $200 memname $200;
             zip = "&targdir./&&zname&i..";
             fid = dopen("targzip");

             if fid = 0 then stop;
             memcount = dnum(fid);

             do i = 1 to memcount;
                memname=dread(fid, i);

                if (first(reverse(trim(memname))) ^= '/') then output;
             end;

             rc = dclose(fid);
        run;

        filename targzip clear;
    %end;

    data &outlist.;
         set work._contents:;
    run;

    proc datasets lib = work nodetails nolist;
         delete _contents:;
        delete _zipfiles;
    run;

%mend listzipcontents;

%listzipcontents(targdir=~/monrepos/import, outlist=work.allfiles);

data _null_;
     set work.allfiles;
     length text $200 code $2000;

     if find(memname, '/') > 0 then do;
        text = cats('%makedir(', substr(memname, 1, find(memname, strip(scan(memname, -1, "/"))) - 2),");");
        put text=;
        rc = dosubl(text);
     end;
    
     code = cats("filename inzip ZIP '", zip, "'", " member='", memname, "';");
     code = cats(code, "filename outzip '~/monrepos/import/CAISSE/", memname, "';");
     code = cats(code, "data _null_; rc = fcopy('inzip', 'outzip'); msg = sysmsg(); put rc= msg=;run;");
     rc = dosubl(code);
run;     



/*
data _null_;
     set work.allfiles;
     length text $200 code $2000;

     if find(memname, '/') > 0 then do;
        text = cats('%makedir(', substr(memname, 1, find(memname, strip(scan(memname, -1, "/"))) - 2),");");
        put text=;
        rc = dosubl(text);
     end;
    
     code = cats("filename inzip ZIP '", zip, "';");
     code = cats(code, "filename outzip '~/monrepos/import/CAISSE/", memname, "';");
     
     code = cats(code, "data _null_; rc = fcopy('inzip', 'outzip');"); 
     code = catx('', code, "lrecl=256 recfm=F length=length eof=eof unbuf;");
     code = catx('', code, "file outzip lrecl=256 recfm=N;");
     code = catx('', code, "input;");
     code = catx('', code, "put _infile_ $varying256. length;");
     code = catx('', code, "return;");
     code = catx('', code, "eof: stop; run;");
     code = catx('', code, "filename outzip clear;");
 
     rc = dosubl(code);
run;     

%makedir(CAISSE/ER-230EJ/STORE001/SALEBACK/CSVBACK/20230831/1510);

filename inzip ZIP '~/monrepos/import/CAISSE.zip';
filename outzip '~/monrepos/import/CAISSE/ER-230EJ/STORE001/SALEBACK/CSVBACK/20230831/1510/MIN01510.csv';
data _null_; 
infile inzip('CAISSE/ER-230EJ/STORE001/SALEBACK/CSVBACK/20230831/1510/MIN01510.csv') 
lrecl=256 recfm=F length=length eof=eof unbuf; 
file outzip lrecl=256 recfm=N; input; put _infile_ $varying256. length; return; eof: stop; 
run; 
filename outzip clear;


%macro extractAll(destination);
    proc sql noprint;
     select zip into: zips1 TRIMMED from allfiles;
     select memname into: file1 TRIMMED from allfiles;
     %let fcount=&sqlobs;
    quit;
    
    %put &=fcount.;
    %put &=zips1.;
    %put &=file1.;

   %do i = 1 %to &fcount;
    filename inzip ZIP "&&zips&i."; 
    data _null_;
        if find("&&file&i.",'/')>0 then do;
          rc = dcreate(scan("&&file&i.",1,'/'),"%sysfunc(getoption(work))");
        end;
    run;
    filename mem "&destination./%bquote(&&file&i.)";
    data _null_;
       infile inzip("&&file&i..") 
           lrecl=256 recfm=F length=length eof=eof unbuf;
       file mem lrecl=256 recfm=N;
       input;
       put _infile_ $varying256. length;
       return;
     eof:
       stop;
    run;
    filename mem clear;
   %end;
%mend;

*%extractAll(destination=%sysfunc(getoption(work)));
%extractAll(destination=~/monrepos/import);
*/