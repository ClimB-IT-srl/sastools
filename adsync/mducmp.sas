/**********************************************************************
 *   PRODUCT:   SAS
 *   VERSION:   9.1
 *   NAME:      %MDUCMP
 *   DATE:      14Jan2004
 *   DESC:      Metadata User Info Compare - Compare user information that
 *              has been extracted from the metadata server with user
 *              information that has been extracted from an external
 *              source or previously extracted from the same server
 *   TEMPLATE SOURCE:  (None Specified.)
 *   UPDATED:   Version 9.2   19Jul2006
 *              Version 9.4M2  7May2014 - Exclude OutboundOnly domains/logins
 *
 ***********************************************************************/

/*---------------------------------------------------------------------------
 *
 *   This macro will compare user info that is contained in a modified form
 *   of the canonical datasets defined by %mduimpc.  The modified form is
 *   created by the %mduextr macro when extracting the user information
 *   from the metadata server.  The differences are stored in datasets that
 *   are also modified from the canonical form.  For each canonical dataset
 *   potentially 3 different datasets can be created.  These dataset will have
 *   the canonical base name plus _add, _delete, or _update indicating that
 *   information in the dataset should be added, deleted, or updated in the
 *   target repository.
 *
 *   Parameters
 *       master = library where the master canonical datasets exist.  These
 *                datasets define what should be in the repository.  These
 *                datasets could have been created by either extracting from
 *                and external source like ActiveDirectory or the Metadata Server.
 *       target = library where the metadata server's user information
 *                has been extracted by the %mduextr.
 *       change = library where the change datasets will be written.
 *       exceptions = a dataset containing filter informtation.  Records that meet
 *                    the filter criteria will be removed from comparison checks.
 *                    Thus they will not show up in any of the change datasets.
 *                    The columns in the dataset are:
 *                    Tablename - name of the canonical table to which the
 *                        filter should be applied.  Possible values are:
 *                        PERSON, LOGINS, EMAIL, PHONE, LOCATION, IDGRPS,
 *                        GRPMEMS, and AUTHDOMAIN.
 *                    Filter - "Where" clause expression (without the WHERE)
 *                        that is be applied against the corresponding table.
 *                    Note - A table may be list multiple times in the exception
 *                        dataset.  All filter entries for a table will be applied.
 *       externonly = Only synchronize information for users or groups that
 *                    originated from an external identity.
 *       authdomcompare = Specifies how AuthenticationDomains will be compared.
 *                    The default value of NAME will cause the comparison
 *                    code to ignore the keyid (externalidentity) associated
 *                    to the authentication domains and just compare the names.
 *                    It also means that the externalonly flag will be ignored
 *                    for AuthDomains.  Because of this, no AuthDomains will be
 *                    flagged for deletion when this option is enabled.
 *                    Valid values are:
 *                          NAME - Compare based on the AuthenticationDomain name.
 *                          KEYID - Compare based on the keyid (ExternalIdentity)
 *                                  associated with the AuthDomain.
 *                    9.2 enhancement -  When using the NAME comparison, if a
 *                       AuthenticationDomain exists in the target datasets,
 *                       but is not found by name in the master datasets,
 *                       then neither the domain or it's logins will be deleted.
 *                       In previous releases the domain was left intact, but
 *                       the logins belonging to imported identities were deleted.
 *                       **To remove an unneeded AuthenticationDomain and it's
 *                       logins, use the "Authentication Domains..." action found
 *                       in the SMC User Manager and Server Manager.
 *
 *
 *   Assumptions:
 *        -The target datasets will have been built by the %mduextr macro
 *         and contain the modified canonical form with objectids and
 *         the extid key indicating that the keyid was extracted from
 *         and external identity associated with the object.
 *        -Master datasets may or may not have been created by mduextr and
 *         thus may not contain objectids or the extid field.  In the case
 *         where these datasets are determined not to contain these fields,
 *         it will be assumed that the info is from an external source and
 *         thus only info originating from an external source should be
 *         compared (must have an associated external identity).
 *---------------------------------------------------------------------------*/


%macro mducmp(master=, target=, change=, exceptions=, externonly=1,authdomcompare=NAME );


%if ("&master" = "")  %then %do;
  %put ERROR:  No master library specified.  Comparison not attempted.;
  %return;
  %end;

%if ("&target" = "")  %then %do;
  %put ERROR:  No target library specified.  Comparison not attempted.;
  %return;
  %end;

%if ("&change" = "")  %then %do;
  %put ERROR:  No change library specified.  Comparison not attempted.;
  %return;
  %end;


%mduimpc(libref=&change);


/* we'll hit the dictionary column table a few times for the */
/* master library.  Go ahead and extract it to the work lib. */
proc sql;
   create table work.columns as select * from dictionary.columns
      where libname=%UPCASE("&master");
quit;


/* Copy the master and target datasets to a work directory and sort them */
/* for the comparison. (Note, an index exists on the datasets and sorting*/
/* in place destroys the indexes.)                                       */
proc sql noprint;
   create table work.mperson as select * from &master..person
          order by keyid;
   create table work.tperson as select * from &target..person
          order by keyid;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="PERSON" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.mperson
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.mperson
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   %if (&externonly = 1) or (&objidexist = 0) %then %do;
      delete from work.mperson where externalkey = 0;
      delete from work.tperson where externalkey = 0;
   %end;
quit;

/* Process the exceptions from the exceptions dataset.  */
/* We'll need to build a dataset with the objectids and */
/* keyid values of the people we remove so that we can  */
/* also remove any related logins, locations, emails,   */
/* and phone numbers from the processing.               */
%if ("&exceptions" ne "" ) %then %do;
proc sql;
   create table work.identityexceptions (
      objid char(17) label="Identity Objectid",
     keyid char(200) label="Identity Keyid"
      );
quit;

data _null_;
   /* get the exception filters for person tables */
   set &exceptions (where=(upcase(tablename) = "PERSON"));
   /* add the objectids and keyids for the soon to be deleted   */
   /* persons in the identityexceptions table.  Note, we'll     */
   /* have to get the objectids and keyids from both the master */
   /* and target versions.                                      */
   attrib line length=$4500;

   if (strip(filter) = "") then delete; /* no filter, skip to next */

   line = "Proc sql; " ||
             " insert into work.identityexceptions " ||
               " select objid, keyid from work.mperson where " || strip(filter) ||
             " Union " ||
               " select objid, keyid from work.tperson where " || strip(filter) || '; ' ||
   /* now delete the rows from both tables */
             " delete from work.mperson where " || strip(filter) || "; " ||
             " delete from work.tperson where " || strip(filter) || "; " ||
             " quit;";
   call execute(trim(line));
   run;

/* For now, don't worry about having duplicates in the */
/* identityexceptions dataset.                         */

%end;  /* exceptions processing for persons. */


/* this will produce a comparison dataset with X's in the */
/* changed characters for the columns of interest.        */
proc compare base=work.mperson compare=work.tperson
   out=work.person_comp outnoequal
   noprint nosummary;
   id keyid;
   var name displayname title description;
 run;

 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..person_delete as select * from work.tperson
        where keyid not in (select keyid from work.mperson);
    create table &change..person_add as select * from work.mperson
        where keyid not in (select keyid from work.tperson);
    /* get the change data from the master dataset. */
   /* note, the subselect will pull the objectid from the target dataset and   */
   /* merge it into the change dataset.  Note, the master dataset may not have */
   /* the objectid in cases of synchronization with an external source.  So,   */
   /* that must be pulled from the target.  In the case where we're sync'ing   */
   /* with a previous metadata extraction, the objectid will be in both master */
   /* and target datasets.  Note, I'm expecting the objectid's to be the same  */
   /* in this case (update).                                                   */
   create table &change..person_update as
        select mperson.keyid, mperson.name, mperson.description, mperson.title, mperson.displayname,
             tperson.objid, mperson.externalkey
           from work.mperson as mperson, work.tperson as tperson
           where mperson.keyid in (select keyid from work.person_comp where _type_ = "DIF") and
               tperson.keyid = mperson.keyid;

   create table &change..person_summary as
        select mperson.keyid, mperson.name, mperson.description, mperson.title, mperson.displayname,
             mperson.objid, mperson.externalkey, tperson.objid as targobjid label="Target ObjectID"
           from work.mperson as mperson left join work.tperson as tperson
                on tperson.keyid = mperson.keyid;

quit;


/***********************************************************************/
/* LOCATION                                                            */
/* Now, let's generate delta datasets for the person locations         */
/* For comparisons, I'm going to treat the keyid and the location type */
/* as the key for comparing records.  This means that the location type*/
/* must be unique among the locations for a particular user.  In other */
/* words, Joe cannot have two Office locations.  He can however have   */
/* an office and an office2 location.                                  */
/***********************************************************************/

/* Copy the master and target datasets to a work directory and sort them */
/* for the comparison. (Note, an index exists on the datasets and sorting*/
/* in place destroys the indexes.)                                       */
proc sql noprint;
   create table work.mlocation as select * from &master..location
          order by keyid, LocationType;
   create table work.tlocation as select * from &target..location
          order by keyid, LocationType;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="LOCATION" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.mlocation
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.mlocation
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   %if (&externonly = 1) or (&objidexist = 0) %then %do;
      delete from work.mlocation where externalkey = 0;
      delete from work.tlocation where externalkey = 0;
   %end;

quit;


/* Process exception filter for the location tables */
%if ("&exceptions" ne "" ) %then %do;

   data _null_;
      /* get the exception filters for location tables */
      set &exceptions (where=(upcase(tablename) = "LOCATION"));
      attrib line length=$4500;

      if (strip(filter) = "") then delete; /* no filter, skip to next */

      /* now delete the rows from both location tables */
      line = "Proc sql;" ||
               " delete from work.mlocation where " || strip(filter) || "; " ||
               " delete from work.tlocation where " || strip(filter) || "; " ||
               " quit;";
      call execute(trim(line));
      run;

   /* go ahead and remove any locations that are to      */
   /* Persons who have been added to the exception list. */
   proc sql;
      delete from work.mlocation where
        keyid in (select distinct keyid from work.identityexceptions);
      delete from work.tlocation where
        keyid in (select distinct keyid from work.identityexceptions);

%end;  /* exceptions processing for location. */



proc compare base=work.mlocation compare=work.tlocation
   out=work.location_comp outnoequal
   noprint nosummary;
   id keyid LocationType;
   var address area city country LocationName postalcode;
 run;

 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..location_delete as select * from work.tlocation
        where keyid || locationtype not in (select keyid || locationtype from work.mlocation);
    create table &change..location_add as select * from work.mlocation
        where keyid || locationtype not in (select keyid || locationtype from work.tlocation);
    /* get the change data from the master dataset. */
   /* note, the subselect will pull the objectid from the target dataset and   */
   /* merge it into the change dataset.  Note, the master dataset may not have */
   /* the objectid in cases of synchronization with an external source.  So,   */
   /* that must be pulled from the target.  In the case where we're sync'ing   */
   /* with a previous metadata extraction, the objectid will be in both master */
   /* and target datasets.  Note, I'm expecting the objectid's to be the same  */
   /* in this case (update).                                                   */
   create table &change..location_update as
        select mlocation.keyid, mlocation.address, mlocation.area, mlocation.city,
               mlocation.country, mlocation.locationtype, mlocation.locationname,
               mlocation.postalcode, tlocation.objid, mlocation.externalkey
           from work.mlocation, work.tlocation
           where mlocation.keyid || mlocation.locationtype in
                     (select keyid || locationtype from work.location_comp where _type_ = "DIF") and
               tlocation.keyid || tlocation.locationtype = mlocation.keyid || mlocation.locationtype;

quit;


/***********************************************************************/
/* EMAIL                                                            */
/* Now, let's generate delta datasets for the EMAIL table              */
/* For comparisons, I'm going to treat the keyid and the email type    */
/* as the key for comparing records.  This means that the email type   */
/* must be unique among the emails for a particular user.  In other    */
/* words, Joe cannot have two Office emails.  He can however have      */
/* an office and an office2 email.                                     */
/***********************************************************************/

/* Copy the master and target datasets to a work directory and sort them */
/* for the comparison. (Note, an index exists on the datasets and sorting*/
/* in place destroys the indexes.)                                       */
proc sql noprint;
   create table work.memail as select * from &master..email
          order by keyid, emailType;
   create table work.temail as select * from &target..email
          order by keyid, emailType;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="EMAIL" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.memail
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.memail
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   %if (&externonly = 1) or (&objidexist = 0) %then %do;
      delete from work.memail where externalkey = 0;
      delete from work.temail where externalkey = 0;
   %end;

quit;


/* Process exception filter for the email tables */
%if ("&exceptions" ne "") %then %do;
   data _null_;
      /* get the exception filters for email tables */
      set &exceptions (where=(upcase(tablename) = "EMAIL"));
      attrib line length=$4500;

      if (strip(filter) = "") then delete; /* no filter, skip to next */

     /* now delete the rows from both email tables */
      line = "Proc sql; " ||
                " delete from work.memail where " || strip(filter) || "; " ||
                " delete from work.temail where " || strip(filter) || "; " ||
                " quit;";
      call execute(trim(line));
      run;

      /* go ahead and remove any emails that are to      */
      /* Persons who have been added to the exception list. */
      proc sql;
         delete from work.memail where
           keyid in (select distinct keyid from work.identityexceptions);
         delete from work.temail where
           keyid in (select distinct keyid from work.identityexceptions);
%end;  /* exceptions processing for email. */


proc compare base=work.memail compare=work.temail
   out=work.email_comp outnoequal
   noprint nosummary;
   id keyid emailType;
   var emailaddr;
 run;

 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..email_delete as select * from work.temail
        where keyid || emailtype not in (select keyid || emailtype from work.memail);
    create table &change..email_add as select * from work.memail
        where keyid || emailtype not in (select keyid || emailtype from work.temail);
    /* get the change data from the master dataset. */
   /* note, the subselect will pull the objectid from the target dataset and   */
   /* merge it into the change dataset.  Note, the master dataset may not have */
   /* the objectid in cases of synchronization with an external source.  So,   */
   /* that must be pulled from the target.  In the case where we're sync'ing   */
   /* with a previous metadata extraction, the objectid will be in both master */
   /* and target datasets.  Note, I'm expecting the objectid's to be the same  */
   /* in this case (update).                                                   */
   create table &change..email_update as
        select memail.keyid, memail.emailaddr, memail.emailtype,
               temail.objid, memail.externalkey
           from work.memail, work.temail
           where memail.keyid || memail.emailtype in
                     (select keyid || emailtype from work.email_comp where _type_ = "DIF") and
               temail.keyid || temail.emailtype = memail.keyid || memail.emailtype;

quit;



/***********************************************************************/
/* PHONE                                                            */
/* Now, let's generate delta datasets for the EMAIL table              */
/* For comparisons, I'm going to treat the keyid and the email type    */
/* as the key for comparing records.  This means that the email type   */
/* must be unique among the emails for a particular user.  In other    */
/* words, Joe cannot have two Office emails.  He can however have      */
/* an office and an office2 email.                                     */
/***********************************************************************/

/* Copy the master and target datasets to a work directory and sort them */
/* for the comparison. (Note, an index exists on the datasets and sorting*/
/* in place destroys the indexes.)                                       */
proc sql noprint;
   create table work.mphone as select * from &master..phone
          order by keyid, phoneType;
   create table work.tphone as select * from &target..phone
          order by keyid, phoneType;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="PHONE" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.mphone
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.mphone
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   %if (&externonly = 1) or (&objidexist = 0) %then %do;
      delete from work.mphone where externalkey = 0;
      delete from work.tphone where externalkey = 0;
   %end;

quit;


/* Process exception filter for the phone tables */
%if ("&exceptions" ne "" ) %then %do;
   data _null_;
      /* get the exception filters for phone tables */
      set &exceptions (where=(upcase(tablename) = "PHONE"));
      attrib line length=$4500;

      if (strip(filter) = "") then delete; /* no filter, skip to next */

      /* now delete the rows from both phone tables */
      line = "Proc sql; " ||
                " delete from work.mphone where " || strip(filter) || "; " ||
                " delete from work.tphone where " || strip(filter) || "; " ||
                " quit;";
      call execute(trim(line));
      run;

      /* go ahead and remove any phones that are to      */
      /* Persons who have been added to the exception list. */
      proc sql;
         delete from work.mphone where
           keyid in (select distinct keyid from work.identityexceptions);
         delete from work.tphone where
           keyid in (select distinct keyid from work.identityexceptions);
%end;  /* exceptions processing for phone. */


proc compare base=work.mphone compare=work.tphone
   out=work.phone_comp outnoequal
   noprint nosummary;
   id keyid phoneType;
   var phoneNumber;
 run;

 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..phone_delete as select * from work.tphone
        where keyid || phonetype not in (select keyid || phonetype from work.mphone);
    create table &change..phone_add as select * from work.mphone
        where keyid || phonetype not in (select keyid || phonetype from work.tphone);
    /* get the change data from the master dataset. */
   /* note, the subselect will pull the objectid from the target dataset and   */
   /* merge it into the change dataset.  Note, the master dataset may not have */
   /* the objectid in cases of synchronization with an external source.  So,   */
   /* that must be pulled from the target.  In the case where we're sync'ing   */
   /* with a previous metadata extraction, the objectid will be in both master */
   /* and target datasets.  Note, I'm expecting the objectid's to be the same  */
   /* in this case (update).                                                   */
   create table &change..phone_update as
        select mphone.keyid, mphone.phoneNumber, mphone.phonetype,
               tphone.objid, mphone.externalkey
           from work.mphone, work.tphone
           where mphone.keyid || mphone.phonetype in
                     (select keyid || phonetype from work.phone_comp where _type_ = "DIF") and
               tphone.keyid || tphone.phonetype = mphone.keyid || mphone.phonetype;

quit;



/***********************************************************************/
/* AuthDomain                                                          */
/* Now, let's generate delta datasets for the AuthDomain table         */
/* For comparisons, I'm going to treat the keyid as the key for        */
/* comparing records.                                                  */
/***********************************************************************/

/* Copy the master and target datasets to a work directory and sort them */
/* for the comparison. (Note, an index exists on the datasets and sorting*/
/* in place destroys the indexes.)                                       */
proc sql noprint;
   create table work.mAuthDomain as select * from &master..AuthDomain
          order by keyid;
   create table work.tAuthDomain as select * from &target..AuthDomain
          order by keyid;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="AUTHDOMAIN" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.mauthdomain
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.mauthdomain
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   /* ***Remember, if we're doing the name comparison, don't    */
   /*    remove any authdoms we're going to compare the names   */
   /*    whether they have external identities or not.          */
   %if ( %upcase(&authdomcompare) = KEYID and
         ( (&externonly = 1) or (&objidexist = 0)) ) %then %do;
      delete from work.mauthdomain where externalkey = 0;
      delete from work.tauthdomain where externalkey = 0;
   %end;

   /* now check the master dataset for the authDomOutboundOnly column */
   select count(*) into :outboundexist from work.columns
      where upcase(memname)="AUTHDOMAIN" and upcase(name)="AUTHDOMOUTBOUNDONLY";
   %if (&outboundexist = 0) %then %do;
       alter table work.mauthdomain
            add authDomOutboundOnly integer format=1.0 label="Outbound Only";
       update work.mauthdomain
            set authDomOutboundOnly = 0;  /* Set default to non-outbound. */
   %end;

   /* now check the master dataset for the authDomTrustedOnly column */
   select count(*) into :trustedexist from work.columns
      where upcase(memname)="AUTHDOMAIN" and upcase(name)="AUTHDOMTRUSTEDONLY";
   %if (&trustedexist = 0) %then %do;
       alter table work.mauthdomain
            add authDomTrustedOnly integer format=1.0 label="Trusted Only";
       update work.mauthdomain
            set authDomTrustedOnly = 0;  /* Set default to non-trusted. */
   %end;

   /* The master dataset may not be well formed in that the OutboundOnly */
   /* and TrustedOnly columns may be empty.  They should contain 0 or    */
   /* 1.  I'm going change any missing values to 0's.                    */
   update work.mauthdomain
      set authDomOutboundOnly = 0 where authDomOutboundOnly is missing;
   update work.mauthdomain
      set authDomTrustedOnly = 0 where authDomTrustedOnly is missing;



   /* now check the target dataset for the authDomOutboundOnly column */
   select count(*) into :outboundexist from dictionary.columns
      where libname=%UPCASE("&target") and upcase(memname)="AUTHDOMAIN" and upcase(name)="AUTHDOMOUTBOUNDONLY";
   %if (&outboundexist = 0) %then %do;
       alter table work.tauthdomain
            add authDomOutboundOnly integer format=1.0 label="Outbound Only";
       update work.tauthdomain
            set authDomOutboundOnly = 0;  /* Set default to non-outbound. */
   %end;

   /* now check the target dataset for the authDomTrustedOnly column */
   select count(*) into :trustedexist from dictionary.columns
      where libname=%UPCASE("&target") and upcase(memname)="AUTHDOMAIN" and upcase(name)="AUTHDOMTRUSTEDONLY";
   %if (&trustedexist = 0) %then %do;
       alter table work.tauthdomain
            add authDomTrustedOnly integer format=1.0 label="Trusted Only";
       update work.tauthdomain
            set authDomTrustedOnly = 0;  /* Set default to non-trusted. */
   %end;

   /* The target dataset may not be well formed in that the OutboundOnly */
   /* and TrustedOnly columns may be empty.  They should contain 0 or    */
   /* 1.  I'm going change any missing values to 0's.                    */
   update work.tauthdomain
      set authDomOutboundOnly = 0 where authDomOutboundOnly is missing;
   update work.tauthdomain
      set authDomTrustedOnly = 0 where authDomTrustedOnly is missing;



quit;

/* Process exception filter for the authdomain tables */
%if ("&exceptions" ne "" ) %then %do;
   data _null_;
      /* get the exception filters for authdomain tables */
      set &exceptions (where=(upcase(tablename) = "AUTHDOMAIN"));
      attrib line length=$4500;

      if (strip(filter) = "") then delete; /* no filter, skip to next */

     /* now delete the rows from both authdomain tables */
      line = "Proc sql; " ||
                 " delete from work.mauthdomain where " || strip(filter) || "; " ||
                 " delete from work.tauthdomain where " || strip(filter) || "; " ||
                 " quit;";
      call execute(trim(line));
      run;
%end;  /* exceptions processing for authdomain. */

/*---------------------------------------------------------------------*
 *  Outbound authentication domains will not be included in the compare
 *  process.  Make temporary datasets containing only the outbound
 *  domains and then purge those entries from the authdomain tables.
 *---------------------------------------------------------------------*/
proc sql noprint;
   create table work.mOutboundDom as select * from work.mauthdomain
          where authDomOutboundOnly ^= 0;
   delete from work.mauthdomain where authDomOutboundOnly ^= 0;
   create table work.tOutboundDom as select * from work.tauthdomain
          where authDomOutboundOnly ^= 0;
   delete from work.tauthdomain where authDomOutboundOnly ^= 0;
quit;

/*--------------------------------------------------------------------*
 * Are we comparing authdoms on keyids only, otherwise compare
 * the NAME only.  Name based comparison is the default.
 *--------------------------------------------------------------------*/
%if ( %upcase(&authdomcompare) = KEYID ) %then %do;

   proc compare base=work.mAuthDomain compare=work.tAuthDomain
      out=work.AuthDomain_comp outnoequal
      noprint nosummary;
      id keyid;
      var authDomName;
    run;

    /* OK, determine which AuthDoms to delete from the metadata and which */
    /* are new.  If the keyid from the source extract is not              */
    /* in the metadata, then we have a new user.  If the keyid is in the  */
    /* metadata, but not in the source extract, then then the user has    */
    /* been deleted.                                                      */
    proc sql;
       create table &change..AuthDomain_delete as select * from work.tAuthDomain
           where keyid not in (select keyid from work.mAuthDomain);
       create table &change..AuthDomain_add as select * from work.mAuthDomain
           where keyid not in (select keyid from work.tAuthDomain);
       /* get the change data from the master dataset. */
      /* note, the subselect will pull the objectid from the target dataset and   */
      /* merge it into the change dataset.  Note, the master dataset may not have */
       /* the objectid in cases of synchronization with an external source.  So,   */
       /* that must be pulled from the target.  In the case where we're sync'ing   */
       /* with a previous metadata extraction, the objectid will be in both master */
       /* and target datasets.  Note, I'm expecting the objectid's to be the same  */
       /* in this case (update).                                                   */
       create table &change..AuthDomain_update as
           select mAuthDomain.keyid, mAuthDomain.authdomname,
                  tAuthDomain.objid, mAuthDomain.externalkey
              from work.mAuthDomain, work.tAuthDomain
              where mAuthDomain.keyid in
                        (select keyid  from work.AuthDomain_comp where _type_ = "DIF") and
                  tAuthDomain.keyid = mAuthDomain.keyid;

       create table &change..AuthDomain_summary as
           select mAuthDomain.keyid, mAuthDomain.authdomname,
                  mAuthDomain.objid, mAuthDomain.externalkey, tAuthDomain.objid as targobjid label="Target ObjectID"
              from work.mAuthDomain left join work.tAuthDomain
                   on tAuthDomain.keyid = mAuthDomain.keyid;

    quit;
%end;  /* comparisons for authdoms using keyids */
/*--------------------------------------------------------------------*
 * Compare based on name only.
 *--------------------------------------------------------------------*/
%else %do;
    /* Remember, we don't delete any Authentication Domains when the */
    /* NAME comparison used.  Also, because we're not keyid based,   */
    /* we will not update existing AuthDoms.  We'll simply check to  */
    /* see if any need to be added.                                  */
    /* NOTE: The name comparison is case insensitive.                */

    /*----------------------------------------------------------------
     * As a result of the "name-only" comparison.  It will be possible
     * to have authentication domains that match but have different
     * keyids.  Because authdom keyids are important in the comparisons
     * for login objects, we will potentially need to "fixup" all the
     * authdom keyids in the logins datasets.  Look for this code later
     * in the logins section of this macro.
     *----------------------------------------------------------------*/
    proc sql;
      /* create empty delete and update Authdom datasets as placeholders */
      /* for future processing that may depend on their existance.       */
       create table &change..AuthDomain_delete as select * from work.tAuthDomain
           where 0;  /* no records will be written. */

       create table &change..AuthDomain_update as
           select mAuthDomain.keyid, mAuthDomain.authdomname,
                  tAuthDomain.objid, mAuthDomain.externalkey
              from work.mAuthDomain, work.tAuthDomain
              where 0;  /* no records will be added. */

       create table &change..AuthDomain_add as select * from work.mAuthDomain
           where upcase(authdomname) not in (select upcase(authdomname) from work.tAuthDomain);

       /* Build dataset that contains all the auth domains from the    */
       /* target dataset which are not found in the master dataset.    */
       /* When we are doing name comparisons, we don't delete any      */
       /* domains.  We need to build a dataset containing these domains*/
       /* so that we don't delete the logins that they contain.  This  */
       /* feature means that SMC created domains and logins that are   */
       /* not found in the master tables will not be deleted during    */
       /* synchronization.                                             */
       create table work.tMissingAuthDoms as
           select tAuthDomain.keyid, tAuthDomain.authdomname,
                  tAuthDomain.objid, tAuthDomain.externalkey, tAuthDomain.objid as targobjid label="Target ObjectID"
              from work.tAuthDomain
              where upcase(tAuthDomain.authdomname) not in
                            (select upcase(authdomname) from work.mAuthDomain);

       create table &change..AuthDomain_summary as
           /* add in the authdoms that are being added. */
           select mAuthDomain.keyid, mAuthDomain.authdomname,
                  mAuthDomain.objid, mAuthDomain.externalkey, tAuthDomain.objid as targobjid label="Target ObjectID"
              from work.mAuthDomain left join work.tAuthDomain
                   on upcase(tAuthDomain.authdomname) = upcase(mAuthDomain.authdomname)
         union
           /* add in the authdoms that found in the master dataset */
           select * from work.tMissingAuthDoms;

       /* It's possible that authdoms exist with the same name in both the */
       /* master and target datasets but differing keyids.  The name       */
       /* comparison code above will build the summary dataset using the   */
       /* keyid of the master dataset.  When the login objects are         */
       /* the processed, we'll need to "fixup" the authdomkeyids of the    */
       /* target logins that they match the keyid of the authdom in the    */
      /* master dataset.  We only care about authdoms whose names match   */
      /* but keyids don't.  So, we'll build a temporary table maps the    */
      /* target keyids to the master keyids.                              */
      create table work.authdomkeymap as
                   select mAuthDomain.keyid as mkeyid, tAuthDomain.keyid as tkeyid
                     from work.mAuthDomain, work.tAuthDomain
                 where upcase(tAuthDomain.authdomname) = upcase(mAuthDomain.authdomname)
                       and tAuthDomain.keyid ^= mAuthDomain.keyid;
    quit;

%end; /* comparison of authdoms based on name */


/***********************************************************************/
/* IDGRPS - IdentityGroups                                             */
/* Now, let's generate delta datasets for the idgrps.                  */
/* For comparisons, I'm going to treat the keyid as the key for        */
/* comparing records.                                                  */
/***********************************************************************/

proc sql noprint;
   create table work.midgrps as select * from &master..idgrps
          order by keyid;
   create table work.tidgrps as select * from &target..idgrps
          order by keyid;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="IDGRPS" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.midgrps
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.midgrps
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   %if (&externonly = 1) or (&objidexist = 0) %then %do;
      delete from work.midgrps where externalkey = 0;
      delete from work.tidgrps where externalkey = 0;
   %end;

quit;

/* Process the exceptions from the exceptions dataset.  */
/* We'll need to add the IdentityGroup objectids and    */
/* keyid values of the groups we remove so that we can  */
/* also remove any related logins or group memberships  */
/* from the comparison processing.                      */

%if ("&exceptions" ne "" ) %then %do;

data _null_;
   /* get the exception filters for person tables */
   set &exceptions (where=(upcase(tablename) = "IDGRPS"));
   attrib line length=$4500;

   if (strip(filter) = "") then delete; /* no filter, skip to next */

   /* add the objectids and keyids for the soon to be deleted   */
   /* idgrps to the identityexceptions table.  Note, we'll      */
   /* have to get the objectids and keyids from both the master */
   /* and target versions.                                      */

   line = "Proc sql; insert into work.identityexceptions " ||
               "select objid, keyid from work.midgrps where " || strip(filter) ||
            " UNION " ||
               "select objid, keyid from work.tidgrps where " || strip(filter) || '; ' ||
   /* now delete the rows from both tables */
            " delete from work.midgrps where " || strip(filter) || "; " ||
            " delete from work.tidgrps where " || strip(filter) || "; " ;
   call execute(trim(line));
   run;

/* For now, don't worry about having duplicates in the */
/* identityexceptions dataset.                         */

%end;  /* exceptions processing for persons. */



/* this will produce a comparison dataset with X's in the */
/* changed characters for the columns of interest.        */
proc compare base=work.midgrps compare=work.tidgrps
   out=work.idgrps_comp outnoequal
   noprint nosummary;
   id keyid;
   var name displayname description grptype;
 run;

 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..idgrps_delete as select * from work.tidgrps
        where keyid not in (select keyid from work.midgrps);
    create table &change..idgrps_add as select * from work.midgrps
        where keyid not in (select keyid from work.tidgrps);
    /* get the &change. data from the master dataset. */
   /* note, the subselect will pull the objectid from the target dataset and   */
   /* merge it into the change dataset.  Note, the master dataset may not have */
   /* the objectid in cases of synchronization with an external source.  So,   */
   /* that must be pulled from the target.  In the case where we're sync'ing   */
   /* with a previous metadata extraction, the objectid will be in both master */
   /* and target datasets.  Note, I'm expecting the objectid's to be the same  */
   /* in this case (update).                                                   */
   create table &change..idgrps_update as
        select midgrps.keyid, midgrps.name, midgrps.description, midgrps.grptype, midgrps.displayname,
             tidgrps.objid, midgrps.externalkey
           from work.midgrps as midgrps, work.tidgrps as tidgrps
           where midgrps.keyid in (select keyid from work.idgrps_comp where _type_ = "DIF") and
               tidgrps.keyid = midgrps.keyid;

   create table &change..idgrps_summary as
        select midgrps.keyid, midgrps.name, midgrps.description, midgrps.grptype, midgrps.displayname,
             midgrps.objid, midgrps.externalkey, tidgrps.objid as targobjid label="Target ObjectID"
           from work.midgrps as midgrps left join work.tidgrps as tidgrps
                on tidgrps.keyid = midgrps.keyid;

quit;

/* In 9.2 we added the ability to load and sync roles.  However, the groupType and */
/* PublicType should only be set when the group/role is added.  It should never    */
/* get changed after creation.  The reason for this is that groups and roles       */
/* participate in security in very different ways.  Simply switching a group to a  */
/* role or role to group would leave potentially leave security settings in        */
/* an incorrect usage.  For this reason, the change loading macros will only set   */
/* the groupType and Public type when the IdentityGroup is created.                */
/* Synchrionization will continue, but the groupType/PublicType will not change.   */
/* Because the grptype change is not propgated, we want to print a message to the  */
/* log warning that this situation was detected but that the group/role will not   */
/* be changed to the other type.                                                   */
/* Note, We use call execute with the %put macro because we get improved message   */
/* formatting with the macro version of put (wraps at word boundaries).            */
proc sql;
   create table work.cgrptype as select midgrps.* from work.midgrps inner join work.tidgrps on tidgrps.keyid = midgrps.keyid
                                    where upcase(midgrps.grptype) ^= upcase(tidgrps.grptype);
   quit;

data _null_;
   set work.cgrptype;
   format line $500.;
   line = '%put %nrquote(WARNING:  Change of GroupType for IdentityGroup with keyid = "' || trim(keyid) || '" detected.  Change loading macros ' ||
          '%%mduchgl() and %%mduchglb() will ignore this change.  IdentityGroups are not allowed to automatically change their ' ||
          'GroupType after they are created.); %put;';
   call execute(trim(line));

   run;



/*-----------------------------------------------------------------------
 * GRPMEMS - IdentityGroup Memberships
 * Now, let's generate delta datasets for the idgrps.
 * Grpmems is just a listing of associaitons.  There are only two colums.
 * One for the group keyid and one for the member keyid (which can be
 * either a Person or an IdentityGroup).  So, there really isn't
 * any object to update here.  Just creation or deletion of associations
 * between groups and their members.  With this in mind, we'll only
 * generate _ADD and _DELETE datasets that list the group membership
 * that should be added or deleted.
 *
 * If the group is listed in the idgrps_delete dataset, then there is no
 * point of listing those associations in the grpmems_delete dataset.
 * Deletion of the group will implicitly delete all the associations
 * to it.  Furthermore, if a group is not listed in the summary set of
 * groups, then we also should not explicitly delete those associaitons.
 * Those associations may be to groups that do not have external identities
 * are being treated as exceptions to the synchronization process. If we were to
 * delete those associations we would essentially break those groups.
 *
 * In addition to the keyids for groups and members, well also populate
 * the _add and _delete change datasets with the objectids of the groups
 * and members if they already exist and an indication of wether the
 * member is a Person or IdentityGroup.
 *----------------------------------------------------------------------*/

proc sql;
   create table work.mgrpmems as select * from &master..grpmems
          order by grpkeyid, memkeyid;
   create table work.tgrpmems as select * from &target..grpmems
          order by grpkeyid, memkeyid;

   /* don't worry about adding the objid and extid keys for */
   /* the groupmems master dataset.  That table only has    */
   /* associations between groups and members.  The idgrps  */
   /* and person tables have been altered and have had the  */
   /* appropriate records removed.  (In the case where we're*/
   /* doing an external only comparison.)  This being the   */
   /* case, the change datasets will only contain           */
   /* associations between externally sourced identities    */
   /* that should be added or deleted.                      */
   /*                                                       */
   /* NOTE: The routine that generates the synchronizing    */
   /* XML add and delete associated members to a group.     */
   /* It cannot rewrite the entire list because it may not  */
   /* have the entire list and end-up removing SMC created  */
   /* associations to an imported group.                    */
quit;

/* Process exception filter for the grpmems tables */
%if ("&exceptions" ne "" ) %then %do;
   data _null_;
      /* get the exception filters for grpmems tables */
      set &exceptions (where=(upcase(tablename) = "GRPMEMS"));
      attrib line length=$4500;

      if (strip(filter) = "") then delete; /* no filter, skip to next */

     /* now delete the rows from both grpmems tables */
      line = "Proc sql; " ||
                " delete from work.mgrpmems where " || strip(filter) || "; " ||
                " delete from work.tgrpmems where " || strip(filter) || "; " ||
                " quit;";
      call execute(trim(line));
      run;

      /* go ahead and remove any grpmems that are to idgroups or */
      /* Persons who have been added to the exception list.      */
      proc sql;
         delete from work.mgrpmems where
           grpkeyid in (select distinct keyid from work.identityexceptions) or
          memkeyid in (select distinct keyid from work.identityexceptions);
         delete from work.tgrpmems where
           grpkeyid in (select distinct keyid from work.identityexceptions) or
          memkeyid in (select distinct keyid from work.identityexceptions);
%end;  /* exceptions processing for phone. */



 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..grpmems_delete as select * from work.tgrpmems
        where grpkeyid || memkeyid not in (select distinct grpkeyid || memkeyid from work.mgrpmems);

    create table &change..grpmems_add as select * from work.mgrpmems
        where grpkeyid || memkeyid not in (select distinct grpkeyid || memkeyid from work.tgrpmems);

    /* now, lets add the objects (if known) back into the add and delete datasets */
   alter table &change..grpmems_delete
      add grpobjid char(17) label="Group ObjectId",
          memobjid char(17) label="Member ObjectId",
         memobjtype char(30) label="Member Type";

    alter table &change..grpmems_add
      add grpobjid char(17) label="Group ObjectId",
          memobjid char(17) label="Member ObjectId",
         memobjtype char(30) label="Member Type";
    /*************************************************/
    /* fixup the entries in the grpmems_delete table */
    /*************************************************/
    /* if the group exists in the target idgrp dataset, then get the object id */
    update &change..grpmems_delete as memstbl
      set grpobjid = (select objid from &target..idgrps where idgrps.keyid = memstbl.grpkeyid);
    update &change..grpmems_delete as memstbl
      set memobjid = (select objid from &target..idgrps where idgrps.keyid = memstbl.memkeyid);

      /* since we only have member IdentityGroup objectids at this point, set the membertype. */
   update &change..grpmems_delete
      set memobjtype = "IdentityGroup"
       where memobjid is not missing;

   /* add the person member objectids */
    update &change..grpmems_delete as memstbl
      set memobjid = (select objid from &target..person where person.keyid = memstbl.memkeyid)
      where memobjid is missing;  /* don't overwrite the group member objids */

   /* Now, anything that has a memobjid but no memobjtype is a Person, set the membertype. */
   update &change..grpmems_delete
      set memobjtype = "Person"
       where memobjtype is missing and memobjid is not missing;

    /* Now, for any remaining members that don't have an objectid, search the _add */
   /* datasets for a matching key and set the type.  It can be assumed that if it */
   /* Isn't a new identityGroup, then it must be a new Person.  So only search the*/
   /* the new groups explicitly and set person implicitly.                        */
   update &change..grpmems_delete
      set memobjtype = "IdentityGroup"
       where memobjtype is missing and memobjid is missing and
             memkeyid in (select keyid from &change..idgrps_add);
   update &change..grpmems_delete
      set memobjtype = "Person"
       where memobjtype is missing;

   /* remove any associations that are to groups which do not appear in the     */
   /* idgrps_summary dataset.  This would include those groups which have been  */
   /* deleted and those that exceptions.  (This includes the exception that we  */
   /* are not synchronizing againt SMC created groups.)  The groups could either */
   /* be a member or main group. Also removed those to deleted Persons.         */
   /* remove the "deletes" for groups that aren't in the summary */
   delete from &change..grpmems_delete
        where  grpmems_delete.grpkeyid not in (select distinct keyid from &change..idgrps_summary);
   /* remove the "deletes" for members which are groups and are not in the summary */
   delete from &change..grpmems_delete
        where  grpmems_delete.memobjtype = "IdentityGroup" AND
               grpmems_delete.memkeyid not in (select distinct keyid from &change..idgrps_summary);
   /* remove the "deletes" for members which are persons and are not in the summary */
   delete from &change..grpmems_delete
        where  grpmems_delete.memobjtype = "Person" AND
               grpmems_delete.memkeyid not in (select distinct keyid from &change..person_summary);

    /*************************************************/
    /* fixup the entries in the grpmems_add table    */
    /*************************************************/
    /* if the group exists in the target idgrp dataset, then get the object id */
    update &change..grpmems_add as memstbl
      set grpobjid = (select objid from &target..idgrps where idgrps.keyid = memstbl.grpkeyid);
    update &change..grpmems_add as memstbl
      set memobjid = (select objid from &target..idgrps where idgrps.keyid = memstbl.memkeyid);
   /* since we only have member IdentityGroup objectids at this point, set the membertype. */
   update &change..grpmems_add
      set memobjtype = "IdentityGroup"
       where memobjid is not missing;

   /* add the person member objectids */
    update &change..grpmems_add as memstbl
      set memobjid = (select objid from &target..person where person.keyid = memstbl.memkeyid)
       where memobjid is missing;  /* if you leave out the where, you delete */
                                  /* the memobjids for the group members    */
                                  /* obtained above.                        */
   /* Now, anything that has a memobjid but no memobjtype is a Person, set the membertype. */
   update &change..grpmems_add
      set memobjtype = "Person"
       where memobjtype is missing and memobjid is not missing;


    /* Now, for any remaining members that don't have an objectid, search the _add */
   /* datasets for a matching key and set the type.  It can be assumed that if it */
   /* Isn't a new identityGroup, then it must be a new Person.  So only search the*/
   /* the new groups explicitly and set person implicitly.                        */
   update &change..grpmems_add
      set memobjtype = "IdentityGroup"
       where memobjtype is missing and memobjid is missing and
             memkeyid in (select keyid from &change..idgrps_add);
   update &change..grpmems_add
      set memobjtype = "Person"
       where memobjtype is missing;


quit;



/***********************************************************************
 * Logins
 * Now, let's generate delta datasets for the logins table.
 * Rules to Note:
 *   An Identity (Person or IdentityGroup) may have multiple logins.
 *   A specific userid may appear in multiple logins, however the
 *      userid must be unique within an AuthenticationDomain.  (In
 *      other words, I may have the same userid in 5 different logins.
 *      But each of those logins must belong to a different AuthDomain.
 *
 * Because of these rules, the keyid, authdomkeyid, and userid fields
 * of the login makeup the keys for comparison between the logins
 * datasets.  However, that only leaves the password field to be
 * compared, and we're not going to compare passwords because we can't
 * extract that information from any source and we would simply end
 * up removing valid password info from the repository.  So, this
 * being said, there will be no logins_update dataset created by this
 * code.  All login related changes result in an add or a delete.
 *
 * **Change in 9.4M2 - With the addition of "Outbound Only" authentication
 * domans, the possibility exists that a login with the same userid may
 * actually be owned by a different user or group.  Logins that are
 * associated with outbound domains are not subject to the ownership
 * restrictions.  Because outbound logins are not likely to be good
 * candidates for synchronization, they are purged from the working
 * datasets.  They will not be compared and will not be included in the
 * add, update, or delete datasets.
 *
 * Note:  Because the behavior of the Authdomcompare option can create
 *        a situation where a AuthenticationDomain can exist in both
 *        Target and Master datasets and have different keyids.  We
 *        will run thru the temporary login datasets and fixup the
 *        authdomkeyids and objectids such that the logins that refer
 *        to a particular authentication domain will have the same keyid
 *        as is in the authdomain_summary dataset.
 ***********************************************************************/

/* Copy the master and target datasets to a work directory and sort them */
/* for the comparison. (Note, an index exists on the datasets and sorting*/
/* in place destroys the indexes.)                                       */
/* Logins to outbound authdomains are excluded in the copy.              */
proc sql noprint;
   create table work.mlogins as select * from &master..logins
          where authdomkeyid not in (select keyid from work.mOutboundDom)
          order by keyid, authdomkeyid, userid;
   create table work.tlogins as select * from &target..logins
          where authdomkeyid not in (select keyid from work.tOutboundDom)
          order by keyid, authdomkeyid, userid;

   /* now check the master dataset for the objid column */
   select count(*) into :objidexist from work.columns
      where upcase(memname)="LOGINS" and upcase(name)="OBJID";
   %if (&objidexist = 0) %then %do;
       alter table work.mlogins
            add objid char(17) format=$17. label="ObjectId" ,
                externalkey num format=8.  label="External Keyid";
       update work.mlogins
            set externalkey = 1;  /* assume keyid is external because there was no objid. */
   %end;

   /* remove observations that don't have an external identity. */
   /* We're only synchronizing stuff from external sources.     */
   %if (&externonly = 1) or (&objidexist = 0) %then %do;
      delete from work.mlogins where externalkey = 0;
      delete from work.tlogins where externalkey = 0;
   %end;


quit;


/* Process exception filter for the logins tables */
%if ("&exceptions" ne "" ) %then %do;
   data _null_;
      /* get the exception filters for logins tables */
      set &exceptions (where=(upcase(tablename) = "LOGINS"));
      attrib line length=$4500;

      if (strip(filter) = "") then delete; /* no filter, skip to next */

     /* now delete the rows from both logins tables */
      line = "Proc sql; " ||
                " delete from work.mlogins where " || strip(filter) || "; " ||
                " delete from work.tlogins where " || strip(filter) || "; " ||
                " quit;";
      call execute(trim(line));
      run;

      /* go ahead and remove any logins that are to Persons   */
      /* or IdGrps who have been added to the exception list. */
      proc sql;
         delete from work.mlogins where
           keyid in (select distinct keyid from work.identityexceptions);
         delete from work.tlogins where
           keyid in (select distinct keyid from work.identityexceptions);

%end;  /* exceptions processing for logins. */

   /* If Auth Domains are being compared by NAME only, then remove  */
   /* any logins from the target dataset that are associated to     */
   /* authentication domains which do not exist in the master       */
   /* datasets.  This will keep us from deleting logins that were   */
   /* created in the smc for authdoms that are also created in the  */
   /* only.                                                         */
   %if ( %upcase(&authdomcompare) = NAME ) %then %do;
      proc sql;
          delete from work.tlogins where
            authdomkeyid in (select distinct keyid from work.tMissingAuthDoms);
          quit;

   %end;


   /* fixup the authdomkeyids to account for the effects of just comparing */
   /* authdom names rather than keyids.  The tlogins may refer to domains  */
   /* whose keyid is different in the master.  The master version is the   */
   /* one we'll use.  So, fixup the keyids using the info in the           */
   /* work.authdomkeymap dataset.                                          */
   %if (%upcase(&authdomcompare) ^= KEYID) %then %do;
      proc sql;
        update work.tlogins
           set authdomkeyid = (select mkeyid from work.authdomkeymap
                                         where tkeyid = authdomkeyid)
          where tlogins.authdomkeyid in (select tkeyid from work.authdomkeymap);
       quit;

   %end;


 /* OK, determine which people to delete from the metadata and which  */
 /* are new.  If the keyid from the source extract is not             */
 /* in the metadata, then we have a new user.  If the keyid is in the */
 /* metadata, but not in the source extract, then then the user has   */
 /* been deleted.                                                     */
 proc sql;
    create table &change..logins_delete as select * from work.tlogins
        where keyid || authdomkeyid || userid not in
              (select keyid || authdomkeyid || userid from work.mlogins);
    create table &change..logins_add as select * from work.mlogins
        where keyid || authdomkeyid || userid not in
              (select keyid || authdomkeyid || userid from work.tlogins);

quit;

/* Delete temporary datasets created during this macro.                         */
/* Note:  If the macro variable _mducmp_nodelete_ is defined, then the deletes */
/*        will be skipped.  This would be useful in debugging.                 */
%if (not %symexist(_mducmp_nodelete_)) %then %do;
   proc datasets library=work MEMTYPE=data NOLIST NOWARN;
      delete columns;
      delete mperson;
      delete tperson;
      delete identityexceptions;
      delete person_comp;
      delete mlocation;
      delete tlocation;
      delete location_comp;
      delete memail;
      delete temail;
      delete email_comp;
      delete mphone;
      delete tphone;
      delete phone_comp;
      delete mAuthDomain;
      delete tAuthDomain;
      delete tOutboundDom;
      delete mOutboundDom;
      delete AuthDomain_comp;
      delete tMissingAuthDoms;
      delete authdomkeymap;
      delete midgrps;
      delete tidgrps;
      delete idgrps_comp;
      delete mgrpmems;
      delete tgrpmems;
      delete mlogins;
      delete tlogins;
      delete cgrptype;
   quit;

%end;



%mend mducmp;
