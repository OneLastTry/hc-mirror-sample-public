Class Custom.Loader
{

Parameter AUTOMIRROR = 1;

/// this method is called automatically when the container is initiated
ClassMethod Load() As %Status
{
    if '$data(^DemoLoaded) {
        set ^DemoLoaded = 1
        if ..#AUTOMIRROR {
            // import code
            do ##class(%SYSTEM.OBJ).ImportDir("/code","*.int;*.cls;*.mac;*.xml","ck",,1)

            // start mirror process
            job $classmethod("Custom.AutoMirror","Run")
        }
    }
    return $$$OK
}

}
