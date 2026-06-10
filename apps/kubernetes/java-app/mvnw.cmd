@REM Licensed to the Apache Software Foundation (ASF) under one
@REM or more contributor license agreements.  See the NOTICE file
@REM distributed with this work for additional information
@REM regarding copyright ownership.
@REM
@REM Maven Wrapper Windows batch script

@IF "%__MVNW_ARG0_NAME__%"=="" (SET "__MVNW_ARG0_NAME__=%~nx0")
@SET ___MAVEN_CMD_LINE_ARGS=%*

@SET "MAVEN_PROJECTBASEDIR=%~dp0"
@SET "WRAPPER_JAR=%MAVEN_PROJECTBASEDIR%.mvn\wrapper\maven-wrapper.jar"
@SET "WRAPPER_PROPERTIES=%MAVEN_PROJECTBASEDIR%.mvn\wrapper\maven-wrapper.properties"

@IF EXIST "%WRAPPER_JAR%" GOTO execute

@FOR /F "usebackq tokens=1,2 delims==" %%A IN ("%WRAPPER_PROPERTIES%") DO (
    @IF "%%A"=="wrapperUrl" SET "WRAPPER_URL=%%B"
)
@echo Downloading Maven Wrapper from %WRAPPER_URL%...
@powershell -Command "&{[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%WRAPPER_URL%', '%WRAPPER_JAR%')}"

:execute
@IF "%JAVA_HOME%"=="" (
    SET "JAVA_CMD=java"
) ELSE (
    SET "JAVA_CMD=%JAVA_HOME%\bin\java"
)

"%JAVA_CMD%" -classpath "%WRAPPER_JAR%" "-Dmaven.multiModuleProjectDirectory=%MAVEN_PROJECTBASEDIR%" org.apache.maven.wrapper.MavenWrapperMain %___MAVEN_CMD_LINE_ARGS%
