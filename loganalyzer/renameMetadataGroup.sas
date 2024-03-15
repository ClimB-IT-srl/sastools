options metaserver="iprd-sas-01.statec.etat.lu" metaport=8561 metauser="sasadm@saspw" 
        metapass="{SAS003}A8C6820A8E630F0850DB235AE3E5FD477FE91430C88064EE75A9330CA293CCD05330" metarepository="Foundation";

data work.changenames;
     length oldname newname $256.;
     infile datalines dsd;  
     input oldname $ newname $;
     datalines;
ICB, PG-STATEC-RL-SAS-ProjectICB
Project Bop, PG-STATEC-RL-SAS-ProjectBop
Project Extrastat, PG-STATEC-RL-SAS-ProjectExtrastat
Project Intrastat, PG-STATEC-RL-SAS-ProjectIntrastat
Project Rappels Intrastat, PG-STATEC-RL-SAS-ProjectRappelsIntrastat
;
run;

data work.identitygroups (keep = uri oldname newname rc);
     length uri $256;  
     nobj = 1; n = 1;
     set work.changenames;
     do while(nobj >= 0);
        nobj = metadata_getnobj(cats("omsobj:IdentityGroup?@Name='", oldname, "'"), n, uri);
        rc = metadata_setattr(uri, "Name", newname); 
        n = n + 1;
     end;
run;

data work.stproc;
     length stpuri stpname usageversion treeuri stpdesc $256;
     call missing (of _all_);
run;
 
data work.stproc;
    set work.stproc;
    length treeuri query stpuri $256;
    i + 1;
    query = "omsobj:ClassifierMap?@PublicType='StoredProcess'";
    do while(0 < metadata_getnobj(query, i, stpuri));
       i + 1;
       rc1 = metadata_getattr(stpuri, "Name", stpname);
       rc2 = metadata_getnasn(stpuri, "Trees", 1, treeuri);
       rc3 = metadata_getattr(stpuri, "Desc", stpdesc);
       keep stpdesc;
       rc4 = metadata_getattr(stpuri, "UsageVersion", UsageVersion);
       keep usageversion;
       output;
    end;
    keep stpuri stpname treeuri;
run;


options metaserver="iprd-sas-01.statec.etat.lu" metaport=8561 metauser="sasadm@saspw" 
        metapass="{SAS003}A8C6820A8E630F0850DB235AE3E5FD477FE91430C88064EE75A9330CA293CCD05330" metarepository="Foundation";

data work.changenames;
     length oldname newname $256.;
     infile datalines dsd;  
     input oldname $ newname $;
     datalines;
Project Bop, CN=PG-STATEC-RL-SAS-Users,OU=Default,OU=Permission Group,OU=STATEC,OU=Entities,OU=Identities,DC=gouv,DC=etat,DC=lu
Project Extrastat, CN=PG-STATEC-RL-SAS-Users,OU=Default,OU=Permission Group,OU=STATEC,OU=Entities,OU=Identities,DC=gouv,DC=etat,DC=lu
Project Intrastat, CN=PG-STATEC-RL-SAS-Users,OU=Default,OU=Permission Group,OU=STATEC,OU=Entities,OU=Identities,DC=gouv,DC=etat,DC=lu
;
run;

data work.identitygroups (keep = uri oldname newname rc);
     length uri $256;  
     nobj = 1; n = 1;
     set work.changenames;
     do while(nobj >= 0);
        nobj = metadata_getnobj(cats("omsobj:IdentityGroup?@Name='", oldname, "'"), n, uri);
        rc = metadata_setattr(uri, "Name", newname); 
        n = n + 1;
     end;
run;

