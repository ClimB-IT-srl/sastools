%macro list_files(dir, pre, ext);
    %local filrf rc did memcnt name i;
    %let rc = %sysfunc(filename(filrf, &dir.));
    %let did = %sysfunc(dopen(&filrf.));
    
    %do i = 1 %to %sysfunc(dnum(&did.));   

        %let name = %qsysfunc(dread(&did., &i.));
             
        %if %qupcase(%qscan(&name., -1, .)) = %upcase(&ext.) and %qupcase(%qsubstr(&name., 1, %length(&pre.))) = %upcase(&pre.) %then %do;
            filename = "&name.";
            dir = "&dir.";
            date = "%qupcase(%qscan(&dir., -2, /))";
            hour = "%qupcase(%qscan(&dir., -1, /))";
            output;
        %end;
        %else %if %qscan(&name., 2, .) = %then %do;
            %list_files(&dir./&name., &pre., &ext.);
        %end;

    %end;
    
    %let rc = %sysfunc(dclose(&did.));
    %let rc = %sysfunc(filename(filrf));     

%mend list_files;


data work.csvfiles;
     length date $8. hour $4. dir $100. filename $12.;
     %list_files(~/monrepos/import/CAISSE/CAISSE/ER-230EJ/STORE001/SALEBACK/CSVBACK, PLU, csv);
run;

data work.csvfiles (drop = text rc);
     set work.csvfiles;
     length text $500.;
     text = cats('proc import datafile = "', dir, '/', filename, '" out=work.dsn', _N_);
     text = catx(' ', text, 'dbms = csv replace; guessingrows = max; run;');
     text = cats(text, 'data work.dsn', _N_, '; set work.dsn', _N_, '; length date $8. hour $4. tva $3.;');
     text = cats(text, 'date = "', date, '";');
     text = cats(text, 'hour = "', hour, '";');
     text = cats(text, 'if total ne 0;');
     text = cats(text, 'if no > 30 then tva = "6%"; else tva = "21%";');
     text = cats(text, 'run;');
     rc = dosubl(text);
run;

data work.monrepos;
     length No 8. Desc $15. COUNT TOTAL 8. date $8. hour $4. tva $3.;
     delete;
run;

data _null_;
     set work.csvfiles end = last;
     length text $500.;
     text = cats('proc append base=work.monrepos data=work.dsn', _N_);
     text = catx(' ', text, 'force; run;');
     rc = dosubl(text);
run;

proc sql;
     create table work.labels as 
     (select distinct desc, no from work.monrepos 
     where total ne 0);
quit;

proc sql noprint;
     update work.monrepos as a
     set desc = (select b.desc from work.labels as b
                 where a.no = b.no);
quit;

proc means data = work.monrepos;
     var total;
     class desc date;
     output out = work.summary sum= / autoname;
run;

proc means data = work.monrepos;
     var total;
     class tva date;
     output out = work.tva sum= / autoname;
run;

proc tabulate data = work.monrepos out = work.desc (keep = desc date total_sum);
     var total;
     class desc date;
     table desc * date, total;
run;

proc tabulate data = work.monrepos out = work.tva (keep = tva date total_sum);
     var total;
     class tva date;
     table tva * date, total;
run;

proc sort data = work.desc;
     by desc date;
run;

proc transpose data = work.desc(rename=(total_sum=total)) out = work.descdata (drop=_name_);
     by desc;
     var total;
     id date;
run;

proc sort data = work.tva;
     by tva date;
run;

proc transpose data = work.tva(rename=(total_sum=total)) out = work.tvadata (drop=_name_);
     by tva;
     var total;
     id date;
run;


