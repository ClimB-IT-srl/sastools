/* debug options */
* options mprint mlogic symbolgen;
options nomprint nomlogic nosymbolgen;
%*put _USER_; 

/* Session and Environment Variables */
options metaserver="iprd-sas-01.statec.etat.lu" /* network name/address of the      */
                                        /*   metadata server.               */
                                        
        metaport=8561               /* Port Metadata Server is listening on.*/

        metauser="sasadm@saspw"  /* Domain Qualified Userid for          */
                                    /*   connection to metadata server.     */

/*      metapass=""         /* Password for userid above.           */
 	metapass="{SAS003}A8C6820A8E630F0850DB235AE3E5FD477FE91430C88064EE75A9330CA293CCD05330"
        metaprotocol=bridge         /* Protocol for Metadata Server.        */  

        metarepository=foundation;  /* Default location of user information */
                                    /*   is in the foundation repository.   */
        
/****************************************************************************/
/* The following macro variables supply connection parameters for the       */
/* Active Directory (AD) Server containing the user and group information.  */ 
/****************************************************************************/  

%let ADServer = "gouv.etat.lu"; /* network name/address of   */
                                               /*   the AD server.          */

%let ADPort   = 636;                         /* Port on which LDAP interface*/
                                             /* is listening. 389 is a      */
                                             /* standard port.              */

%let ADPerBaseDN ="OU=IAM,OU=Mail Account,OU=STATEC,OU=Entities,OU=Identities,DC=gouv,DC=etat,DC=lu";              /* Specify the Distinguished */
                                                                                                                      /* Name in the LDAP hierarchy  */
                                                                                                                      /* where People searches begin.*/

%let ADGrpBaseDN ="OU=Default,OU=Permission Group,OU=STATEC,OU=Entities,OU=Identities,DC=gouv,DC=etat,DC=lu"; /* Specify the Distinguished */
                                                                                                                      /* Name in the LDAP hierarchy  */
                                                                                                                      /* where Group searches begin. */


%let ADBindUser = "CN=STATEC SAS Accounts sync - statec_sas_adsync,OU=Service,OU=Mail Account,OU=STATEC,OU=Entities,OU=Identities,DC=gouv,DC=etat,DC=lu";      /* Userid which will connect   */
                                                                                                                                                      /* to the AD server and extract*/
                                                                                                                                                      /* the information.            */
                                             
%let ADBindPW = "U2O6pB455Qoc79ZKtJin8r207j5kq";                  /* Password for Userid above.  */

options set=LDAP_TLSMODE 1;

/* Session variables */
%let approot=D:\software\ADSync;
%let adtableroot=&approot./tables;
%let xmlroot=&approot./xml;

/* libname that stores copies of a number of tables */
libname copyt "&adtableroot./copytables";

/* Don't delete the SASWORK files */
/* Recuperate XML request & response files */
%let _mduimplb_nodelete_=1;										/* SASWORK files - don't delete */
%let _mduimplb_outrequest_=&approot./xml/request;				/* XML request files */
%let _mduimplb_outresponse_=&approot./xml/response;				/* XML response files */

/* Specify the directory  for the extracted AD data (master tables)*/
libname extract "&adtableroot./extractad";

/* Specify the directory  for the canonical tables */
libname canon "&adtableroot./canontables";
%let importlibref=canon;

/* Specify the directory for the extracted  metadata (target tables)*/
libname meta "&adtableroot./extractmeta";

/* Specify the directory  for the comparison output (change tables)*/
libname updates "&adtableroot./updatesmeta";

/* Specify the directory for the exceptions table */
libname except "&adtableroot./exceptions";
/*data except.adexceptions;
	length tablename $32 filter $256;
	infile cards;
	input tablename $ filter $;
	cards;
logins upcase(keyid)="CZZ4M"
person upcase(keyid)="CZZ4M"
email upcase(keyid)="CZZ4M"
location upcase(keyid)="CZZ4M"
phone upcase(keyid)="CZZ4M"*/
;

/* Extract identity information from AD (master)*/
%let _EXTRACTONLY = 1; 
%include "&approot./importad.sas";

/* Extract identity information from the metadata (target).*/
%mduextr(libref=meta);

/* Compare AD (master) to metadata (target)*/ 
%mducmp(master=canon, target=meta, change=updates/*, exceptions=except.adexceptions*/);

/* Validate the change tables.*/
%mduchgv(change=updates, target=meta, temp=work, errorsds=work.mduchgverrors);

/* Load  the  changes into the metadata */
/* ORIGINAL */
*%mduchglb(change=updates); 

/* WITH ERROR CHECK */
%macro exec_mduchglb;
   %if (&MDUCHGV_ERRORS ^= 0) %then %do;
      %put ERROR: Validation errors detected by %nrstr(%mduchgv). Load not attempted.;
      %return;
      %end;
   %mduchglb(change=updates);
%mend;

%exec_mduchglb;

/* Delete macro variables */
%symdel _EXTRACTONLY _mduimplb_nodelete_ _mduimplb_outrequest_ _mduimplb_outresponse_;
