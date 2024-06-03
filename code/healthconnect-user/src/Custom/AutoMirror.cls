Include %occInclude

Class Custom.AutoMirror Extends %RegisteredObject
{

Parameter MIRRORSET = "HEALTHCONNECT";

Parameter VIP = "loadbalancer";

ClassMethod Run() As %Status
{
    set tSC = $$$OK
    try {
        new $namespace
        set $namespace = "%SYS"
        // wait until mirror is identified as active
        set mirrorActive = 0
        do {
            hang 5
            set mirrorActive = ##class(SYS.Mirror).IsMirrorStarted(..#MIRRORSET)
        } while ('mirrorActive)

        // wait until member is configured
        set memberStatus = ""
        do {
            hang 5
            kill this,other
            do ##class(SYS.Mirror).GetFailoverMemberStatus(.this,.other)
            set memberType = $listget(this,3)
            set memberStatus = $listget(this,4)
        } while (memberStatus'="Active")

        new $namespace
        set $namespace = "USER"

        // enable HS_Services
        do ..ResetHSServices()
        // initiate the process for the correct member (Primary,Backup)
        set tSC = $classmethod($classname(),"Create"_memberType)
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod ResetHSServices() As %Status [ Internal, Private ]
{
	set tSC = $$$OK
	try { 
		set ns = $namespace
		set $namespace = "%SYS"
		kill param
		do ##class(Security.Users).Get("HS_Services",.param) 
		set param("Enabled") = 1
		set param("ChangePassword") = 0
		set param("Password") = "HS_Services"
		do ##class(Security.Users).Modify("HS_Services",.param)
		set $namespace = ns
	} catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod CreatePrimary()
{
    set tSC = $$$OK
    try {
        // update the network host name
        set tSC = ..UpdateNetworkHostNameA()
        // mirror HSSYS on the primary
        set tSC = ..MirrorHSSYSA()
        // try to wait for the backup node to be ready
        hang 60
        // install mirrored foundation namespace
        set tSC = ..InstallFoundationA()
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod CreateBackup()
{
    set tSC = $$$OK
    try {
        // try to wait for the primary node to be ready
        hang 20
        // mirror HSSYS on the backup
        set tSC = ..MirrorHSSYSB()
        // setup the "Mirror Monitor Launch Task" task on the backup
        set tSC = ..TaskHSSYSB()
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod MirrorHSSYSA()
{
    set tSC = $$$OK
    try {
        new $namespace
        set $namespace = "%SYS"
        set dir = $piece(##class(Config.Databases).DatabaseByName("hssys"),"^",3)
        // add HSSYS to the mirror set
        set tSC = ##class(SYS.MirrorConfiguration).AddDatabaseToMirrorSet(dir,..#MIRRORSET)
        set db = ##Class(SYS.Database).%OpenId(dir)
        // dismount HSSYS
        set tSC = db.Dismount()
        // copy HSSYS
        set tSC = ##class(%File).CopyFile(dir_"IRIS.DAT","/tmp/IRIS.DAT")
        // mount HSSYS
        set tSC = db.Mount()
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod MirrorHSSYSB()
{
    set tSC = $$$OK
    try {
        new $namespace
        set $namespace = "%SYS"
        set dir = $piece(##class(Config.Databases).DatabaseByName("hssys"),"^",3)
        set db = ##Class(SYS.Database).%OpenId(dir)
        // dismount HSSYS
        set tSC = db.Dismount()
        // copy HSSYS from the primary
        set tSC = ##class(%File).CopyFile("/tmp/IRIS.DAT",dir_"IRIS.DAT",)
        // mount HSSYS
        do ##class(%Library.File).Delete("/tmp/IRIS.DAT")
        set tSC = db.Mount()
        // activate HSSYS
        set tSC = $SYSTEM.Mirror.DBActivate(dir)
        set params("Action") = "C"
 	    set items(1) = dir
        // catchup HSSYS
 	    set tSC = ##class(%CSP.UI.System.BackgroundTask).RunTask("MirrorActivateCatchupDB",$namespace,.params,.items,.job)
        hang 10
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod TaskHSSYSB()
{
    set tSC = $$$OK
    try {
        new $namespace
        set $namespace = "HSLIB"
        // setup the "Mirror Monitor Launch Task" task
        do ##class(HS.HC.SystemConfig.API).ScheduleTask("HSSYS","HS.Util.Mirror.Task","HSSYS")
        hang 10
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod UpdateNetworkHostNameA()
{
    set tSC = $$$OK
    try {
        // update the network host name
        set ^|"HSSYS"|%SYS("HealthShare","NetworkHostName") = ..#VIP
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

ClassMethod InstallFoundationA()
{
    set tSC = $$$OK
    try {
        new $namespace
        set $namespace = "HSLIB"
        // install mirrored foundation namespace
        set vars("Mirror") = 1
        set namespace = "MIRROREDAUTO"
        set tSC = ##class(HS.Util.Installer.Foundation).Install(namespace,.vars)
        
        set $namespace = namespace
        // auto start production
        set production = namespace_"PKG.FoundationProduction"
        do ##class(Ens.Director).SetAutoStart(production,1)
        do ##class(HS.Director).StartAll()
    } catch (err) {
        set tSC = $$$ADDSC(tSC,err.AsStatus())
    }
    return tSC
}

}
