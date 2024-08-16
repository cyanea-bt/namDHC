onMessage(0x4a, "thread_receiveData")

gui 1: -SysMenu
gui 1:show, hide, % APP_RUN_JOB_NAME
menu tray, noIcon

APP_MAIN_HWND := winExist(APP_MAIN_NAME)
thread_recvData := {}
thread_sendData := {}

thread_log("Started ... ")

; Set up console window
; --------------------------------------------------------------------------------------------
console := new Console()
console.setConsoleTitle(APP_RUN_CONSOLE_NAME)

winSet, Style, ^0x80000 , % "ahk_id " console.getConsoleHWND() ; Remove close button on window

if ( SHOW_JOB_CONSOLE == "no" ) 												; Hide console
	winHide , % "ahk_id " console.getConsoleHWND()

; Handshaking
; --------------------------------------------------------------------------------------------
thread_log("Handshaking with " APP_MAIN_NAME "... ")
while ( !thread_recvData.cmd && !thread_recvData.idx ) {
	thread_log(".")
	sleep 10
	if ( a_index > 1000 ) {
		thread_log("Error handshaking!`n")
		return
	}
}
thread_log("OK!`n"
		. "Starting a " stringUpper(thread_recvData.cmd) " job`n`n"
		. "Working job file: " thread_recvData.workingTitle "`n"
		. "Working directory: " thread_recvData.workingDir "`n")

mergeObj(thread_recvData, thread_sendData)															; Assign thread_recvData to thread_sendData as we will be sending the same info back and forth

thread_sendData.pid := dllCall("GetCurrentProcessId")
thread_sendData.progress := 0
thread_sendData.log := "Preparing " stringUpper(thread_recvData.cmd) " - " thread_recvData.workingTitle
thread_sendData.progressText := "Preparing  -  " thread_recvData.workingTitle
thread_sendData()


; Create output folder if it dosent exist
; -------------------------------------------------------------------------------------------------------------------
if ( thread_recvData.outputFolder ) {
	if ( fileExist(thread_recvData.outputFolder) <> "D" ) {
		if ( createFolder(thread_recvData.outputFolder) ) {
			thread_log("Created directory " thread_recvData.outputFolder "`n")
		}
		else {
			sleep 50
			thread_log("Error creating directory " Error creatingthread_recvData.outputFolder "`n")
			
			thread_sendData.status := "error"
			thread_sendData.log := "Error creating directory " thread_recvData.outputFolder
			thread_sendData.report := "`n" "Error creating directory " thread_recvData.outputFolder "`n"
			thread_sendData.progressText := "Error creating directory  -  " thread_recvData.workingTitle
			thread_sendData.progress := 100
			thread_sendData()
			thread_finishJob()
			exitApp
		}
	}
}

; Zipfile was supplied as source
; -------------------------------------------------------------------------------------------------------------------
if ( thread_recvData.fromFileExt == "zip" ) {

	thread_sendData.status := "unzipping"
	thread_sendData.progress := 0
	thread_sendData.progressText := "Unzipping  -  " thread_recvData.fromFile
	thread_sendData()
	
	tempZipDirectory := DIR_TEMP "\" thread_recvData.fromFileNoExt
	folderDelete(tempZipDirectory, 3, 25, 1) 										; Delete folder and its contents if it exists
	createFolder(tempZipDirectory)													; Create the folder
	
	if ( fileExist(tempZipDirectory) == "D" ) {
		thread_log("Unzipping " thread_recvData.fromFileFull "`nUnzipping to: " tempZipDirectory)
		setTimer, thread_timeout, % (TIMEOUT_SEC*1000)*3 							; Set timeout timer timeout time x2
		if ( fileUnzip := thread_unzip(thread_recvData.fromFileFull, tempZipDirectory) ) {
			thread_sendData.log := "Unzipped " thread_recvData.fromFileFull " successfully"
			thread_sendData.report := "Unzipped " thread_recvData.workingTitle " successfully`n"
			thread_sendData.progress := 100
			thread_sendData.progressText := "Unzipped successfully  -  " thread_recvData.workingTitle
			thread_sendData()
		
			thread_log("Unzipped " thread_recvData.fromFileFull " successfully`n")		
			
			thread_recvData.unzipped := {}
			thread_recvData.unzipped.fromFileFull := fileUnzip.full
			thread_recvData.unzipped.fromFile := fileUnzip.file
			thread_recvData.unzipped.fromFileNoExt := fileUnzip.noExt
			thread_recvData.unzipped.fromFileExt := fileUnzip.ext
			
			mergeObj(thread_recvData, thread_sendData)
		}
		else error := ["Error unzipping file '" thread_recvData.unzipped.fromFileFull "'", "Error unzipping file  -  " thread_recvData.unzipped.fromFileFull]
	}
	else error := ["Error creating temporary directory '" DIR_TEMP "\" thread_recvData.fromFileNoExt "'", "Error creating temp directory"]
	
	setTimer, thread_timeout, off
	
	if ( error ) {
		thread_sendData.status := "error"
		thread_sendData.log := error[1]
		thread_sendData.report := "`n" error[1] "`n"
		thread_sendData.progressText := error[2] "  -  " thread_recvData.workingTitle
		thread_sendData.progress := 100
		thread_sendData()

		if ( fileExist(tempZipDirectory) )
			thread_deleteDir(tempZipDirectory, 1) ; Delete temp directory
		
		thread_finishJob()
		exitApp
	}
}

sleep 10
	
fromFile := thread_recvData.unzipped.fromFileFull ? """" thread_recvData.unzipped.fromFileFull """" : (thread_recvData.fromFileFull ? """" thread_recvData.fromFileFull """" : "" )
toFile := thread_recvData.toFileFull ? """" thread_recvData.toFileFull """" : ""
cmdLine := CHDMAN_FILE_LOC . " " . thread_recvData.cmd . thread_recvData.cmdOpts . (fromFile ? " -i " fromFile : "") . (toFile ? " -o " toFile : "")
thread_log("`nCommand line: " cmdLine "`n`n")

thread_sendData.progress := 0
thread_sendData.log := "Starting " stringUpper(thread_recvData.cmd) " - " thread_recvData.workingTitle
thread_sendData.progressText := "Starting job  -  " thread_recvData.workingTitle

thread_sendData()


; Get starting file size
if ( instr(stringLower(fromFile), "gdi") || instr(stringLower(fromFile), "cue") || instr(stringLower(fromFile), "toc") ) {
	thread_sendData.fileStartSize := 0
	for idx, file in getFilesFromCUEGDITOC(strReplace(fromFile, """", "")) { 	; Remove quotes form filename
		fileGetSize fs, % file  												; if in TOC, GDI or CUE, get starting files sizes in bytes
		fileStartSize += fs
	}
} else {
	fileGetSize fs, % strReplace(fromFile, """", "")  							; Get starting file size in bytes if not a TOC, CUE or GDI
	fileStartSize := fs
}


setTimer, thread_timeout, % (TIMEOUT_SEC*1000) 						; Set timeout timer
output := runCMD(cmdLine, thread_recvData.workingDir, "CP0", "thread_parseCHDMANOutput") ; thread_parseCHDMANOutput is the function that will be called for STDOUT 
setTimer, thread_timeout, off

rtnError := thread_checkForErrors(output.msg)

; CHDMAN was not successful - Errors were detected
; -------------------------------------------------------------------------------------------------------------------
if ( rtnError ) {
	
	if ( inStr(rtnError, "file already exists") == 0 && !thread_recvData.keepIncomplete ) {			; Delete incomplete output files, only delete files that arent "file exists" error
		
		delFiles := deleteFilesReturnList(thread_recvData.toFileFull)

		thread_sendData.log := delFiles <> "" ? "Deleted incomplete file(s): " regExReplace(delFiles, " ,$") : "Error deleting incomplete file(s)!"
		thread_sendData.report := thread_sendData.log "`n"
		thread_sendData.progress := 100
		thread_sendData()
		
		thread_log(thread_sendData.log "`n")
	}
	
	thread_sendData.status := "error"
	thread_sendData.log := rtnError
	thread_sendData.report := "`n" (inStr(thread_sendData.log, "Error") ? "" : "Error: ") thread_sendData.log "`n"
	thread_sendData.progressText := regExReplace(thread_sendData.log, "`n|`r", "") "  -  " thread_recvData.workingTitle
	thread_sendData.progress := 100
	thread_sendData()
	
	thread_finishJob()
	exitApp

}

; CHDMAN was successfull - No errors were detected
; -------------------------------------------------------------------------------------------------------------------
if ( fileExist(tempZipDirectory) ) 
	thread_deleteDir(tempZipDirectory, 1) 														; Always delete temp zip directory and all of its contents

if ( thread_recvData.deleteInputFiles ) {
	
	if ( fileExist(thread_recvData.unzipped.fromFileFull) ) 	; Delete input files of unzipped if requested (and they exist)
		thread_deleteFiles(thread_recvData.unzipped.fromFileFull)

	if ( fileExist(thread_recvData.fromFileFull) ) 				; Delete input source files if requested
		thread_deleteFiles(thread_recvData.fromFileFull)

	if ( fileExist(thread_recvData.workingDir) == "D" )			; Delete input folder only if its not empty
		thread_deleteDir(thread_recvData.workingDir)	
}

if ( inStr(thread_recvData.cmd, "verify") )
	suffx := "verified"
else if ( inStr(thread_recvData.cmd, "extract") )
	suffx := "extracted media"
else if ( inStr(thread_recvData.cmd, "create") )
	suffx := "created"
else if ( inStr(thread_recvData.cmd, "addmeta") )
	suffx := "added metadata" 
else if ( inStr(thread_recvData.cmd, "delmeta") )
	suffx := "deleted metadata" 
else if ( inStr(thread_recvData.cmd, "copy") )
	suffx := "copied metadata" 
else if ( inStr(thread_recvData.cmd, "dumpmeta") )
	suffx := "dumped metadata"

thread_sendData.status := "success"
thread_sendData.log := "Successfully " suffx "  -  " thread_recvData.workingTitle
thread_sendData.progressText := "Successfully " suffx "  -  " thread_recvData.workingTitle
thread_sendData.progress := 100

; Calculate file size savings
fileGetSize, fileFinishSize, % strReplace(toFile, """", "") 	; Get new file size - remove quotes from filename

if ( instr(thread_recvData.cmd, "create") > 0 ) { ; If job is compressing a new CHD, add report of file size savings
	pcnt := (1 - (fileFinishSize / fileStartSize))*100
	bytesSaved := fileStartSize - fileFinishSize
	thread_sendData.report := "`nStarting size: " formatBytes(fileStartSize) " - Finished file size: " formatBytes(fileFinishSize) "`nTotal size saved: " formatBytes(bytesSaved) "  -  Space savings: " pcnt "%"
	thread_sendData.fileStartSize  := fileStartSize
	thread_sendData.fileFinishSize := fileFinishSize
}

thread_sendData.report .= "`n`nSuccessfully " suffx "`n"

thread_sendData()
thread_finishJob()
exitApp



; Thread functions
; ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	
; Check for errors after CHDMAN job
; -----------------------------------
thread_checkForErrors(msg)
{
	errorList := ["Error parsing input file", "Error: file already exists", "Error opening input file", "Error reading input file", "Unable to open file", "Error writing file"
	, "Error opening parent CHD file", "CHD is uncompressed", "No verification to be done; CHD has no checksum", "Error reading CHD file", "Error creating CHD file"
	, "Error opening CHD file", "Error opening parent CHD file", "Error during compression", "Invalid compressor", "Invalid hunk size"
	, "Unit size is not an even divisor of the hunk size", "Unsupported version", "Error getting info on hunk", "Input start offset greater than input file size"
	, "Can't guess CHS values because there is no input file", "Sector size does not apply"
	, "Error reading audio samples", "Error assembling data for frame", "Invalid size string", "Error opening AVI file", "Error reading AVI frame"
	, "CHD is uncompressed", "CHD has no checksum", "Blank hard disks must be uncompressed", "CHS does not apply when creating a diff from the parent"
	, "Invalid CHS string", "Error reading ident file", "Ident file '", "Template '", "Unable to find hard disk metadata in parent CHD"
	, "Error parsing hard disk metadata in parent CHD", "Data size is not divisible by sector size", "Blank hard drives must specify either a length or a set of CHS values"
	, "Error adding hard disk metadata", "Error adding CD metadata", "Uncompressed is not supported"
	, "Error adding AV metadata", "Error adding AVLD metadata", "Hunk size is not an even multiple or divisor of input hunk size"
	, "Error writing cloned metadata", "Error upgrading CD metadata", "Error writing upgraded CD metadata", "Error writing to file; check disk space"
	, "Unable to recognize CHD file as a CD", "Error writing frame", "Unable to find A/V metadata in the input CHD", "Improperly formatted A/V metadata found"
	, "Frame size does not match hunk size for this CHD", "Error reading hunk", "Error writing samples for hunk", "Error writing video for hunk"
	, "Error reading metadata file", "Error: missing either --valuetext/-vt or --valuefile/-vf parameters", "Error: both --valuetext/-vt or --valuefile/-vf parameters specified; only one permitted"
	, "Error adding metadata", "Error removing metadata:", "Error reading metadata:"]
	
	if ( !msg )
		return ""
	
	for idx, thisErr in errorList {																					
		if ( inStr(msg, thisErr) )					; Check if error from chdman output contains an error string in errorlist array
			return thisErr
	}
	return ""
}



; Get chdman std output, parse it and send it to host
; runCMD() calls this function when it has text data and sends it here
;-------------------------------------------------------------------------
thread_parseCHDMANOutput(data, lineNum, cPID) 													
{ 																	
	;global thread_sendData, thread_recvData, CHDMAN_VERSION_ARRAY, APP_MAIN_NAME, TIMEOUT_SEC
	global
	thread_sendData.chdmanPID := cPID ? cPID : ""

	setTimer, thread_timeout, % (TIMEOUT_SEC*1000) 						; Reset timeout timer 
	
	if ( lineNum > 1 ) {
		if ( stPos := inStr(data, "Compressing") ) {
			thread_sendData.status := "compressing"
			,stPos += 13, enPos := inStr(data, "%", false, stPos)		; chdman output: "Compressing, 16.8% complete... (ratio=40.5%)"
			,stPos2 := inStr(data, "(ratio="), enPos2 := inStr(data, "%)",false,0)+2
			,ratio := subStr(data, stPos2, (enPos2-stPos2))
			,thread_sendData.progress := subStr(data, stPos, (enPos-stPos))
			,thread_sendData.progressText := "Compressing -  " ((strLen(thread_sendData.toFile) >= 80)? subStr(thread_sendData.toFile, 1, 66) " ..." : thread_sendData.toFile) (thread_sendData.progress>0 ? "  -  " thread_sendData.progress "% " : "") "  " ratio
		}
		else if ( stPos := inStr(data, "Extracting") ) {
			thread_sendData.status := "extracting"
			,stPos += 12, enPos := inStr(data, "%", false, stPos)		; chdman output: "Extracting, 39.8% complete..."
			,thread_sendData.progress := subStr(data, stPos, (enPos-stPos))
			,thread_sendData.progressText := "Extracting -  " ((strLen(thread_sendData.toFile) >= 90)? subStr(thread_sendData.toFile, 1, 77) " ..." : thread_sendData.toFile) (thread_sendData.progress>0 ? "  -  " thread_sendData.progress "%" : "")
		}
		else if ( stPos := inStr(data, "Verifying") ) {
			thread_sendData.status := "verifying"
			,stPos += 11, enPos := inStr(data, "%", false, stPos)		; chdman output: "Verifying, 39.8% complete..."
			,thread_sendData.progress := subStr(data, stPos, (enPos-stPos))
			,thread_sendData.progressText := "Verifying -  " ((strLen(thread_sendData.fromFile) >= 90)? subStr(thread_sendData.fromFile, 1, 78) " ..." : thread_sendData.fromFile) (thread_sendData.progress>0 ? "  -  " thread_sendData.progress "%" : "") 
		}
		else if ( !inStr(data,"% ") ) { ; Dont capture text that is in the middle of work
			thread_sendData.report := regExReplace(data, "`r|`n", "") "`n"
		}
	}
	else { 																; Wrong chdman version detected
		enPos := inStr(data, "(", false, stPos)
		chdmanVer := trim(subStr(data, 53, (enPos-53)))
		
		if ( !inArray(chdmanVer, CHDMAN_VERSION_ARRAY) )  {
			thread_sendData.status := "error"
			thread_sendData.log := "Error: Wrong CHDMAN version " chdmanVer "`n - Supported versions of CHDMAN are: " arrayToString(CHDMAN_VERSION_ARRAY)
			thread_sendData.report := "Wrong CHDMAN version supplied [" chdmanVer "]`nSupported versions of CHDMAN are: " arrayToString(CHDMAN_VERSION_ARRAY) "`n`nJob cancelled.`n"
			thread_sendData.progressText := "Error - Wrong CHDMAN version -  " thread_recvData.workingTitle
			thread_sendData.progress := 100
			thread_log(thread_sendData.log "`n")
			thread_sendData()
			
			thread_finishJob()
			exitApp
		}
	}
	
	thread_log(data)
	thread_sendData()
	return data
}
	

/*
 Send a message to host
---------------------------------------------------------------------------------------
	What we send home:
		thread_sendData.log				-	(string)  General message as to what we are doing
		thread_sendData.status			-	(string)  "started", "done", "error" or "killed" indicating status of job
		thread_sendData.chdmanPID		-	(string)  PID of this chdman
		thread_sendData.report			- 	(string)  Output of chdman and other data to be prsented to user at the end of the job
		thread_sendData.progress		-	(integer) progress percentage
		thread_sendData.progressText	-	(integer) progressbar text description
		-- and all data from host which was previously sent in object
*/
thread_sendData(msg:="") 
{
	global

	if ( msg == false )
		return
	
	sleep 10
	msg := (msg=="") ? thread_sendData : msg
	sendAppMessage(JSON.Dump(msg), APP_MAIN_NAME " ahk_id " APP_MAIN_HWND)										; Send back the data we've recieved plus any other new info
	thread_sendData.log := ""
	thread_sendData.report := ""
	thread_sendData.status := ""
	sleep 10
}


/*
Recieve messages from host
---------------------------------------------------------------------------------------	
		What we recieve from host:
		q.PID			 - (string)  PID of (this) thread which starts chdman.exe
		q.idx		      - (string)  Job Number in queue
		q.cmd 			 - (string)  The command for chdman to run (ie 'extractcd', 'createhd', 'verify', 'info')
		q.cmdOpts 		 - (string)  The options (with parameters) to pass along to chdman
		q.workingDir 	 - (string)  The input working directory
		q.fromFile 		 - (string)  Input filename without path
		q.fromFileExt	 - (string)  Input file extension
		q.fromFileNoExt  - (string)  Input filename without path or extension
		q.fromFileFull 	 - (string)  Input filename with full path and extension
		q.outputFolder 	 - (string)  The output folder where files will be saved
		q.toFile 		 - (string)  Output filename without path
		q.toFileExt		 - (string)  Output file extension
		q.toFileNoExt 	 - (string)  Output filename without path or extension
		q.toFileFull 	 - (string)  Output filename with full path and extension
		q.fileDeleteList - (array)   Files set to be deleted after job has completed
		q.hostPID		 - (string)  PID of main program
		q.id 			 - (number)  Unique job id
*/
thread_receiveData(wParam, lParam) 
{
	global

	thread_recvData := JSON.Load( strGet(numGet(lParam + 2*A_PtrSize),, "utf-8") )
	
	if ( thread_recvData.KILLPROCESS == "true" && thread_recvData.chdmanPID ) {
		
		thread_sendData.log := "Attempting to cancel " . thread_recvData.workingTitle
		thread_sendData.progressText := "Cancelling -  " thread_recvData.workingTitle
		thread_sendData.progress := 0
		thread_sendData()
		
		thread_log("`nThread cancel signal receieved`n")

		process, close, % thread_recvData.chdmanPID
		sleep 1000
		process, Exist, % thread_recvData.chdmanPID
		
		if ( errorlevel <> 0 ) { ; Process still exists
			thread_sendData.log := "Couldn't cancel " thread_recvData.workingTitle " - Error closing job"
			thread_sendData.progressText := "Couldn't cancel -  " thread_recvData.workingTitle
			thread_sendData.progress := 100
			thread_sendData.report := "`nCancelling of job was unsuccessful`n"
			thread_sendData()
			
			thread_log("`n`nJob couldn't be cancelled!`n")
		}
		else { 
			thread_sendData.status := "cancelled"
			thread_sendData()
			
			if ( !thread_recvData.keepIncomplete && fileExist(thread_recvData.toFileFull) )	{						; Delete incomplete output files if asked to keep 
				delFiles := deleteFilesReturnList(thread_recvData.toFileFull)
				thread_sendData.log := delFiles <> "" ? "Deleted incomplete file(s): " regExReplace(delFiles, " ,$") : "Error deleting incomplete file(s)!"
				thread_sendData.report := job.msgData[pSlot].log "`n"
				thread_sendData.progress := 100
				thread_sendData()
			}
			
			thread_sendData.log := "Job " thread_recvData.idx " cancelled by user"
			thread_sendData.progressText := "Cancelled -  " thread_recvData.workingTitle
			thread_sendData.progress := 100
			thread_sendData.report := "Job cancelled by user`n"
			thread_sendData()										
			
			thread_finishJob()
			
			thread_log("`nJob cancelled by user`n")
			exitApp
		}
	}
}
	

; timer is refreshed on every call of thread_parseCHDMANOutput - if it lands here we assume chdman has timed out
; ------------------------------------------------------------------------------------------
thread_timeout()
{
	global thread_recvData, thread_sendData
	
	thread_sendData.status := "error"
	thread_sendData.progressText := "Error  -  CHDMAN timeout " thread_recvData.workingTitle
	thread_sendData.progress := 100
	thread_sendData.log := "Error: Job failed - CHDMAN timed out"
	thread_sendData.report := "`nError: Job failed - CHDMAN timed out" "`n"
	thread_sendData()
	
	thread_finishJob()				; contains thread_sendData()
	exitApp
}



; Delete files after an unsuccessful completeion of CHDMAN
; -----------------------------------------------------------------------------------------
thread_deleteIncompleteFiles(file) 
{
	global thread_recvData, thread_sendData

	if ( !fileExist(file) )
		return false
}
	
	
	
; Delete input files after a successful completeion of CHDMAN (if specified in options)
; -----------------------------------------------------------------------------------------
thread_deleteFiles(delfile) 
{
	global thread_sendData, thread_recvData
	
	deleteTheseFiles := getFilesFromCUEGDITOC(delfile)					; Get files to be deleted
	if ( deleteTheseFiles.length() == 0 )
		return false
	
	log := "", errLog := ""
	for idx, thisFile in deleteTheseFiles {			
		if ( fileDelete(thisFile, 3, 25) )
			log .= "'" splitPath(thisFile).file "', "
		else
			errlog .= "'" splitPath(thisFile).file "', "
	}
	
	if ( log )
		thread_sendData.log := "Deleted Files: " regExReplace(log, ", $")	
	if ( errLog )
		thread_sendData.log := (log ? log "`n" : "") "Error deleting: " regExReplace(errLog, ", $")									; Remove trailing comma
	
	thread_sendData.report := thread_sendData.log "`n"
	thread_sendData.progress := 100
	thread_sendData()
	
	thread_log(thread_sendData.log "`n")
}


thread_deleteDir(dir, delFull:=0) 
{
	if ( !delFull && !dllCall("Shlwapi\PathIsDirectoryEmpty", "Str", dir) )
		thread_sendData.log := "Error deleting directory '" dir "' - Not empty"
	else
		thread_sendData.log := folderDelete(dir, 5, 50, delFull) ? "Deleted directory '" dir "'" : "Error deleting directory '" dir "'"
	
	thread_sendData.report := thread_sendData.log "`n"
	thread_sendData.progress := 100
	thread_sendData()
	
	thread_log(thread_sendData.log "`n")
}


; Send output to console
;---------------------------------------------------------------------------------------
thread_log(newMsg, concat=true) 
{
	global console
	
	if ( console.getConsoleHWND() )
		console.write(newMsg)
}



; Unzip a file
;http://www.autohotkey.com/forum/viewtopic.php?p=402574
; -----------------------------------------------------
thread_unzip(file, dir)
{
    global thread_recvData, thread_sendData
	
	try {
		psh  := ComObjCreate("Shell.Application")
		zipped := psh.Namespace(file).items().count
		
		setTimer, unzip_showtimer, 500
		psh.Namespace(dir).CopyHere( psh.Namespace(file).items, 4|16 )
		setTimer, unzip_showtimer, off
		
		loop, Files, % regExReplace(dir, "\\$") "\*.*", FR
		{
			zipfile := splitPath(a_LoopFileLongPath)
			if ( zipExtInList := inArray(zipfile.ext, thread_recvData.inputFileTypes) )
				return zipfile			; Use only the first file found in the zip temp dir
		}
		return false
		
		unzip_showtimer:
			thread_sendData.status := "unzipping"
			thread_sendData.progress := ceil((psh.Namespace(dir).items().count/zipped)*100)
			thread_sendData.progressText := "Unzipping  -  " thread_recvData.fromFile
			thread_sendData()
		return
	
	}
	catch e
		return false
}




; Finish the job
; ----------------
thread_finishJob() 
{
	global
	
	sleep 10
	thread_sendData.status := "finished"
	thread_sendData.progress := 100
	thread_log(thread_sendData.log? thread_sendData.log "`nFinished!":"")
	thread_sendData()
	
	if ( SHOW_JOB_CONSOLE == "yes" )	
		sleep WAIT_TIME_CONSOLE_SEC*1000	; Wait x seconds or until user closes window
	exitApp
}