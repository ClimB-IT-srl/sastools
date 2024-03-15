* root directory for libraries and text files;
%let baserep = /sas/prd/software/ldap/data/ ;
%let filerep = /sas/prd/software/ldap/file/ ;
*%let baserep = /export/home/sast/etienne/ldap/ ;
*%let filerep = /export/home/sast/etienne/ldap/ ;

* define key to identify LDAP imported data;
%let fromldap = LDAP Imported;

* metadata server connection information;
*%let MDserver = zdmmetaa01 ;
%let MDserver = zdmmetap01 ;
%let port = 8561 ;
%let user = sasadm@saspw ;
%let pw = pw4sas2adm ;
%let repository = Foundation ;

* Assign libraries;
libname can "&baserep.canonical";
libname md "&baserep.metadata";
libname change "&baserep.changes";

filename outxml "&filerep.LDAP.xml";
libname outxml xml "&filerep.LDAP.xml";

* setup connection to the MDServer;
options metaserver = &MDServer. metaport = &port. metauser="&user."  
        metapass="&pw." metaprotocol=bridge metarepository=&repository.;

data _null_;
     file outxml; 
     length g_entryname $200 g_Attribute $100 g_Value $100 g_filter $100;
     length m_entryname $200 m_Attribute $100 m_Value $100 m_filter $100;
     length p_entryname $200 p_Attribute $100 p_Value $100 p_filter $100;

     g_rc = 0; 
     g_handle = 0;

     * define connection infos;
     server = "dps.finbel.intra";
     port = 389;
     group = "ou=Groups,dc=iam,dc=finbel,dc=intra";  
     people = "ou=People,dc=iam,dc=finbel,dc=intra";  
     bindDN = "iam-uid=sasiam,ou=Technical,dc=iam,dc=finbel,dc=intra";  
     Pw = "23FGH2hffg6";

     **** SECTION 1: look for groups ****;

     * perform in SAS the equivalent to:
     * ldapsearch -u -h 'dps.finbel.intra' -p 389 -D 'iam-uid=sasiam,ou=Technical,dc=iam,dc=finbel,dc=intra' ;
     * -w 23FGH2hffg6 -b 'ou=Groups,dc=iam,dc=finbel,dc=intra' -s sub 'cn=SG_DWH*' cn  ;

     * open connection to LDAP server;
     call ldaps_open(g_handle, server, port, group, bindDn, Pw, g_rc);
     if g_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end;
     else putlog "LDAPS_OPEN call successful.";

     g_shandle = 0;
     g_num = 0;

     * search for the existing groups;
     g_filter = "cn=SG_DWH*";
     g_attrs = " cn";

     * search the LDAP directory;
     call ldaps_search(g_handle, g_shandle, g_filter, g_attrs, g_num, g_rc);
     if g_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end;
     else putlog "LDAPS_SEARCH call successful. Num group entries: " g_num;

     * Store result in XML;
     put '<?xml version="1.0" encoding="windows-1252" ?>' /@3 '<TABLE>';

     do g_eIndex = 1 to g_num;
        g_numAttrs = 0;
        g_entryname = '';

        * retrieve each entry name and number of attributes;
        call ldaps_entry(g_shandle, g_eIndex, g_entryname, g_numAttrs, g_rc);
        if g_rc ne 0 then do;
           msg = sysmsg();
           putlog msg;
        end;

        * for each attribute, retrieve name and values;
        do g_aIndex = 1 to g_numAttrs;
           g_Attribute = '';
           g_numValues = 0;
           call ldaps_attrName(g_shandle, g_eIndex, g_aIndex, g_Attribute, g_numValues, g_rc);
           if g_rc ne 0 then do;
              msg = sysmsg();
              putlog msg;
           end;

           do g_vIndex = 1 to g_numValues;
              call ldaps_attrValue(g_shandle, g_eIndex, g_aIndex, g_vIndex, g_value, g_rc);

              if g_rc ne 0 then do;
                 msg = sysmsg();
                 putlog msg;
              end;
              else do; 

     **** SECTION 2: for each retrieved group, look for user memberships ****;

     * perform in SAS the equivalent to:
     * ldapsearch -u -h 'dps.finbel.intra' -p 389 -D 'iam-uid=sasiam,ou=Technical,dc=iam,dc=finbel,dc=intra' ;
     * -w 23FGH2hffg6 -b 'ou=Groups,dc=iam,dc=finbel,dc=intra' -s sub 'cn=SG_DWH-ICT_LOGEU' uniqueMember  ;

     m_rc = 0; 
     m_handle = 0;

     * open connection to LDAP server;
     call ldaps_open(m_handle, server, port, group, bindDn, Pw, m_rc);
     if m_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end;
     else putlog "MEMBERSHIP LDAPS_OPEN call successful.";

     m_shandle = 0;
     m_num = 0;

     * search for the existing groups;
     m_filter = "cn=" || g_value;
     m_attrs = " uniqueMember";

     * search the LDAP directory;
     call ldaps_search(m_handle, m_shandle, m_filter, m_attrs, m_num, m_rc);
     if m_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end;
     else putlog "MEMBERSHIP LDAPS_SEARCH call successful. Num members in group: " m_num;

     do m_eIndex = 1 to m_num;
        m_numAttrs = 0;
        m_entryname = '';

        * retrieve each entry name and number of attributes;
        call ldaps_entry(m_shandle, m_eIndex, m_entryname, m_numAttrs, m_rc);
        if m_rc ne 0 then do;
           msg = sysmsg();
           putlog msg;
        end;

        * for each attribute, retrieve name and values;
        do m_aIndex = 1 to m_numAttrs;
           m_Attribute = '';
           m_numValues = 0;
           call ldaps_attrName(m_shandle, m_eIndex, m_aIndex, m_Attribute, m_numValues, m_rc);
           if m_rc ne 0 then do;
              msg = sysmsg();
              putlog msg;
           end;

           do m_vIndex = 1 to m_numValues;
              call ldaps_attrValue(m_shandle, m_eIndex, m_aIndex, m_vIndex, m_value, m_rc);

              if m_rc ne 0 then do;
                 msg = sysmsg();
                 putlog msg;
              end;
              else do; 

                   **** SECTION 3: for each retrieved member, look for its description ****;

                   * perform in SAS the equivalent to:
                   * ldapsearch -u -h 'dps.finbel.intra' -p 389 -D 'iam-uid=sasiam,ou=Technical,dc=iam,dc=finbel,dc=intra' ;
                   * -w 23FGH2hffg6 -b 'iam-uid=lmathieu,ou=People,dc=iam,dc=finbel,dc=intra' ''  uid cn mail ;

                   put @6 '<USER>' ;

                   p_rc = 0; 
                   p_handle = 0;

                   * open connection to LDAP server specific for people queries;
                   call ldaps_open(p_handle, server, port, m_value, bindDn, Pw, p_rc);
                   if p_rc ne 0 then do;
                      msg = sysmsg();
                      putlog msg;
                   end;
                   else putlog "PEOPLE LDAPS_OPEN call successful for dn: " m_value;

                   p_shandle = 0;
                   p_num = 0;

                   * define search filter and attributes;
                   p_filter = " ";
                   p_attrs = " uid cn mail";

                   * search the LDAP directory;
                   call ldaps_search(p_handle, p_shandle, 'cn=*', p_attrs, p_num, p_rc);
                   if p_rc ne 0 then do;
                      msg = sysmsg();
                      putlog msg;
                   end;
                   else putlog "PEOPLE LDAPS_SEARCH call successful.";

                   if (p_num = 1) then do;
                      * remove trailing information from group and start outputing data;
                      grpname = tranwrd(g_value, "SG_DWH-", "");
                      grpname = tranwrd(grpname, "SG_DWH_", "");
                      put @9 '<usertype>' grpname +(-1) '</usertype>';
                      put @9 '<keyid>' m_value +(-1) '</keyid>';

                      p_numAttrs = 0;
                      p_entryname = '';

                      * retrieve each entry name and number of attributes;
                      call ldaps_entry(p_shandle, 1, p_entryname, p_numAttrs, p_rc);
                      if p_rc ne 0 then do;
                         msg = sysmsg();
                         putlog msg;
                      end;

                      * for each attribute, retrieve name and values;
                      do p_aIndex = 1 to p_numAttrs;
                         p_Attribute = '';
                         p_numValues = 0;
                         call ldaps_attrName(p_shandle, 1, p_aIndex, p_Attribute, p_numValues, p_rc);
                         if p_rc ne 0 then do;
                            msg = sysmsg();
                            putlog msg;
                         end;

                         do p_vIndex = 1 to p_numValues;
                            call ldaps_attrValue(p_shandle, 1, p_aIndex, p_vIndex, p_value, p_rc);
                            if p_rc ne 0 then do;
                               msg = sysmsg();
                               putlog msg;
                            end;
                            else do; 
                                 put @9 '<' p_Attribute +(-1) '>' p_value +(-1) '</' p_Attribute +(-1) '>';
                            end;
                         end;
                      end;
                   end;
                   else putlog "PEOPLE LDAPS_SEARCH didn't returned an unique entry for dn: " value;
					     
                   * free people search resources;
                   call ldaps_free(p_shandle, p_rc);
                   if p_rc ne 0 then do;
                      msg = sysmsg();
                      putlog msg;
                   end;
                   else putlog "PEOPLE LDAPS_FREE call successful.";

                   * close connection to LDAP server for people search;
                   call ldaps_close(p_handle, p_rc);
                   if rc ne 0 then do;
                      msg = sysmsg();
                      putlog msg;
                   end; 
                   else putlog "PEOPLE LDAPS_CLOSE call successful.";

                   put @6 '</USER>' ;
                   **** END SECTION 3: members ****;

              end;
           end;
        end;
     end;

     * free people search resources;
     call ldaps_free(m_shandle, m_rc);
     if m_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end;
     else putlog "MEMBERSHIP LDAPS_FREE call successful.";

     * close connection to LDAP server for people search;
     call ldaps_close(m_handle, m_rc);
     if m_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end; 
     else putlog "MEMBERSHIP LDAPS_CLOSE call successful.";
     **** END SECTION 2: user memberships ****;

              end;
           end;
        end;
     end;

     put @3 '</TABLE>';

     * free search resources;
     call ldaps_free(g_shandle, g_rc);
     if g_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end;
     else putlog "LDAPS_FREE call successful.";

     * close connection to LDAP server;
     call ldaps_close(g_handle, g_rc);
     if g_rc ne 0 then do;
        msg = sysmsg();
        putlog msg;
     end; 
     else putlog "LDAPS_CLOSE call successful.";
     **** END SECTION 2: groups ****;
run;

* working library name;
%let lib=work ;

%macro checkds(dsn);
    %if %sysfunc(exist(&dsn)) %then %do;
        data &lib..ldap;
             set outxml.USER;
             rename uid = LDAPdn;
             rename mail = userid;
             rename cn = fullname;
             * retrieve DB name from group name and append LDAP_ as prefix;
             groupname = "LDAP_" || upcase(substr(usertype, index(usertype, "_") + 1));
             if index(usertype, "-") then dptname = substr(usertype, 1, index(usertype, "_") - 1);
			 else dptname = "";
        run;
    %end;
    %else %do;
        data &lib..ldap;
		     attrib uid mail cn groupname dptname userid usertype length=$50.;
			 delete;
        run;
    %end;
%mend checkds;

* Invoke the macro, pass a non-existent data set name to test ;
%checkds(outxml.USER);

* create table with users;
data &lib..user
     &lib..internuser
     ;
	 set &lib..ldap;
     if index(userid,"@guest") > 0 then do;
        userid = substr(userid,1,index(userid,"@guest") - 1);
        output &lib..internuser;
     end;
     else output &lib..user;
run;

proc sort data=&lib..user(drop = usertype groupname dptname) nodupkeys ;
     by userid ;
run ;

proc sort data=&lib..internuser(drop = usertype groupname dptname) nodupkeys ;
     by userid ;
run ;

* create table with groups;
proc sort data=&lib..ldap(keep = groupname dptname where=(groupname ^= "")) out=&lib..group nodupkeys ;
     by groupname ;
run ;

* create internal account macro;
%macro createInternalAccounts(submit=0);
    %let dsid = %sysfunc(open(&lib..internuser));

	data &lib..guestuser;
         attrib ldapdn userid fullname keyid length=$50.;
         delete;
    run;

    %if &dsid %then %do;
        %syscall set(dsid);
        %let nobs=%sysfunc(attrn(&dsid,nobs));

        %do i=1 %to &nobs;
            %let rc=%sysfunc(fetch(&dsid));
            %let ldapdn=%sysfunc(getvarc(&dsid,%sysfunc(varnum(&dsid,ldapdn))));
            %let userid=%sysfunc(getvarc(&dsid,%sysfunc(varnum(&dsid,userid))));
            %let fullname=%sysfunc(getvarc(&dsid,%sysfunc(varnum(&dsid,fullname))));
            %let keyid=%sysfunc(getvarc(&dsid,%sysfunc(varnum(&dsid,keyid))));
            data &lib..guestuser(keep=ldapdn userid fullname keyid);
                 call missing(rc, uri);
				 n=1;
                 ldapdn="&ldapdn.";
                 userid="&userid.";
                 fullname="&fullname.";
                 keyid="&keyid.";
                 omsUri = "omsobj:Person?@Name='&userid.'";
                 rc=metadata_getnobj(omsUri,n,uri);
                 put rc=;
                 put uri=;

                 if rc ne 1 then do;
				    if &submit. = 1 then do;
                       call execute(
"proc metadata repos=""Foundation"" in="" 
<ADDMETADATA>
<METADATA>
<InternalLogin Name='&userid.' PasswordHash='KpmXvXnpy/m2oKZTXM20vQ==' Salt='e+pk'>
<ForIdentity>
<Person Id='&keyid.' Desc='&fromldap.' Name='&userid.' DisplayName='&fullname.'/></ForIdentity>
</InternalLogin>
</METADATA>
<REPOSID>$METAREPOSITORY</REPOSID>
<NS>SAS</NS>
<FLAGS>268436480</FLAGS>
<OPTIONS/>
</ADDMETADATA>"";
run ;"
                       );
					end;
                    output;
                 end;
				 else delete;
             run;
        %end;
             
        %let rc = %sysfunc(close(&dsid));
    %end;
%mend;

* defines synchronisation macros;
%macro extrDWMD(itlib=&lib., canlib=work, submit=0);

    %createInternalAccounts(submit=&submit.);

    %mduimpc(libref=&canlib);

    data &persontbla;
         %definepersoncols;
         set &itlib..user;
         name  = trim(left(fullname)) ;
         displayname  = trim(left(fullname)) ;
         description = "&fromldap.";
		 if index(userid,"@guest") > 0 then do;
            name = substr(userid,1,index(userid,"@guest") - 1);
         end;
    run;

    data &phonetbla ;
         %definephonecols;
         delete;
    run;

    * Create the location Table;
    data &locationtbla ;
         %definelocationcols;
         delete;
    run;

    * create the email Table;
    data &emailtbla ;
         %defineemailcols;
         set &itlib..user;
         emailAddr  = userid ;
         emailType  = "Office" ;
    run;
	 
    * Create the idgrp Table;
    data &idgrptbla ;
         %defineidgrpcols;
         set &itlib..group;
         keyid = groupname;
         name = groupname;
         description = trim(groupname) || " &fromldap. ";
         if dptname ne "" then description = description || " - Department: " || dptname;
    run;

    * Create the grpmems Table;
    data &idgrpmemstbla;
         %defineidgrpmemscols;
         set &itlib..ldap;
         grpkeyid = groupname;
         memkeyid = keyid;
    run;

    * Create authdomain Table;
    data &authdomtbla ;
         %defineauthdomcols;
         keyid="domkeyLDAP";
         authDomName="LDAP";
    run;

    * Create logins Table;
    data &logintbla;
         %definelogincols;
         set &itlib..user;
         password = "";
         authdomkeyid = "domkeyLDAP";
    run;

    * Now, load the information contained in the datasets above into the;
    * metadata server. Defaults will read the datasets from the work;
    * library;
    %mduimpl(libref=&canlib, submit=&submit);

%mend;

%macro upchngMD(itlib=&lib., canlib=canlib, mdlib=mdlib, chlib=chlib, submit=0);
    * Create the base canonical tables;
    %extrDWMD(itlib=&itlib, canlib=&canlib, submit=0);

    * extract user info from the metadata server;
    %mduextr(libref=&mdlib);

    * retrieve any user already existing as internal and update their keyid in can tables;
    proc sql noprint;
        create table work.loginstmp as 
        select a.keyid, b.keyid as intern
        from can.logins a, md.logins b
        where upcase(a.userid) = upcase(b.userid) and a.keyid ^= b.keyid;
    quit;
    run;

    proc sql noprint;
        create table work.guesttmp as 
        select a.keyid, b.keyid as intern
        from &lib..internuser a, md.person b
        where upcase(a.userid) = upcase(b.name) and a.keyid ^= b.keyid;
    quit;
    run;

	proc sql ;
         update can.logins a
         set keyid = 
             (select intern 
              from work.loginstmp b
              where b.keyid = a.keyid 
             )  
         where keyid in
             (select keyid
              from work.loginstmp b 
             );
    quit;
    run;

	proc sql ;
         update can.person a
         set keyid = 
             (select intern 
              from work.loginstmp b
              where b.keyid = a.keyid 
             )  
         where keyid in
             (select keyid
              from work.loginstmp b 
             );
    quit;
    run;

    proc append base=work.loginstmp data=work.guesttmp force;
    run;

	proc sql ;
         update can.grpmems a
         set memkeyid = 
             (select intern 
              from work.loginstmp b
              where b.keyid = a.memkeyid 
             )  
         where memkeyid in
             (select keyid
              from work.loginstmp b 
             );
    quit;
    run;

	proc sql ;
         update can.idgrps a
         set keyid = 
             (select intern 
              from work.loginstmp b
              where b.keyid = a.keyid 
             )  
         where keyid in
             (select keyid
              from work.loginstmp b 
             );
    quit;
    run;

	proc sql ;
         update can.location a
         set keyid = 
             (select intern 
              from work.loginstmp b
              where b.keyid = a.keyid 
             )  
         where keyid in
             (select keyid
              from work.loginstmp b 
             );
    quit;
    run;

	proc sql ;
         update can.phone a
         set keyid = 
             (select intern 
              from work.loginstmp b
              where b.keyid = a.keyid 
             )  
         where keyid in
             (select keyid
              from work.loginstmp b 
             );
    quit;
    run;

    * compare the two set of data;
    %mducmp(master=&canlib, target=&mdlib, change=&chlib, externonly=0);

	proc sql ;
         delete from change.logins_add  
         where keyid in
             (select intern
              from work.loginstmp b 
             );
         delete from change.email_add  
         where keyid in
             (select intern
              from work.loginstmp b 
             );
         delete from change.location_add  
         where keyid in
             (select intern
              from work.loginstmp b 
             );
         delete from change.person_add  
         where keyid in
             (select intern
              from work.loginstmp b 
             );
         delete from change.phone_add  
         where keyid in
             (select intern
              from work.loginstmp b 
             );
    quit;
    run;

    * retrieve groups from "md" that are not in "can" and add their members to grpmems_delete;
    data work.mdgroups(keep=keyid objid);
         set md.idgrps(where=(description contains "&fromldap."));
    run;

    proc sql noprint;
         delete from work.mdgroups
         where keyid in (select keyid from can.idgrps);
    quit;
    run;

    proc sql noprint;
         create table work.mdgrpmems as
         select a.keyid as grpkeyid, 
                a.objid as grpobjid, 
                b.memkeyid, 
                c.objid as memobjid, 
                "Person" as memobjtype
         from work.mdgroups a, md.grpmems b, md.person c
         where a.keyid = b.grpkeyid
           and b.memkeyid = c.keyid;
    quit;
    run;

    proc append base=change.grpmems_delete data=work.mdgrpmems;
    run;

    * Users and groups are not delete by this program, only group memberships !!!;
    proc sql noprint;
         delete from change.authdomain_add;
    quit;
    run;

    proc sql noprint;
         delete from change.authdomain_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.authdomain_update;
    quit;
    run;

    proc sql noprint;
         delete from change.email_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.location_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.idgrps_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.location_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.logins_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.person_delete;
    quit;
    run;

    proc sql noprint;
         delete from change.phone_delete;
    quit;
    run;

    * remove technical account from logins;
    proc sql noprint;
         delete from md.logins
         where userid = "sastsrv" 
           and keyid = "iam-uid=jelsocht,ou=People,dc=iam,dc=finbel,dc=intra";
    quit;
    run;

    * validate changes;
    %mduchgv(change=&chlib, target=&mdlib, temp=work, errorsds=work.mduchgverrors);

    * load the changes if no error detected;
    %if (&MDUCHGV_ERRORS ^= 0) %then %do;
        %put ERROR: Validation errors detected by %nrstr(%mduchgv). Load not attempted.;
        %return;
    %end;

    %mduchgl(change=&chlib, submit=&submit);

    * free resources;
    proc datasets library=work MEMTYPE=data NOLIST NOWARN;
         delete group;
         delete ldap;
         delete mdgroups;
         delete mdgrpmems;
         delete user;
    quit;

    * Reporting;
    ods html body="&filerep.LoadReport.html" ;

    title "List of added groups" ;
    proc print data=change.idgrps_add(keep=name) ;
    run ;

    title "List of updated groups" ;
    proc print data=change.idgrps_update(keep=name) ;
    run ;

    title "List of added GUEST users" ;
    proc print data=&lib..guestuser(keep=fullname) ;
    run ;

    title "List of added users" ;
    proc print data=change.person_add(keep=name) ;
    run ;

    title "List of updated users" ;
    proc print data=change.person_update(keep=name) ;
    run ;

    title "List of added group memberships" ;
    proc print data=change.grpmems_add ;
    run ;

    title "List of deleted group memberships" ;
    proc print data=change.grpmems_delete ;
    run ;

    title ;

    ods html close ;

%mend;

option mprint symbolgen;

********* MACRO CALL PART ***********;

***********************************************************************;
* submit=0 => process macros without loading into the metadata server *;
* submit=1 => process macros and load into the metadata server        *;
***********************************************************************;

* Use the next command line for an initial full load ;
*%extrDWMD(itlib=&lib., canlib=can, submit=1);
* Use the next command line for an update;
%upchngMD(itlib=&lib., canlib=can, mdlib=md, chlib=change, submit=1);

********* END OF MACRO CALL PART ***********;

