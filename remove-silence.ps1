function removeSilenceFromMp4 () {
  Param ([switch]$Reconvert)

  if (-not (get-command ffmpeg -ErrorAction SilentlyContinue)) {
    "ffmpeg is not found, add it to PATH"
    return
  }
  
  function FileAvailable([string]$filePath){
    if (-not (Test-Path $filePath)) {
      return $false
    }
    Rename-Item $filePath $filePath -ErrorVariable errs -ErrorAction SilentlyContinue
    return -not ($errs.Count -ne 0)
  }

  function get-OutputFileName ($file) {
    (
      $file.directoryname + 
      [IO.Path]::DirectorySeparatorChar + 
      $file.basename + "_removed_silence" + $file.extension
    )
  }

  function get-mp4s ($alreadyProcessedFiles) {
    Get-ChildItem *.mp4 -Exclude *_removed_silence.mp4 | 
      Where-Object {
        $outputfile = get-OutputFileName $_
        ((-not $alreadyProcessedFiles[$_.fullname]) -and 
          ($_.length -gt 0kb) -and 
          (FileAvailable $_.fullname) -and 
          ($Reconvert -or (-not (test-path $outputfile))))
      }
  }

  $alreadyProcessedFiles = @{}
  $files = get-mp4s $alreadyProcessedFiles

  while ($files.length -gt 0) {
    $file = $files[0]

    $videoFilterFile = "vf.tmp"
    $audioFilterFile = "af.tmp"
    # silences.tmp is used for silencedetect-output

    Write-host ("Detecting mean volume in " + $file.name + "...")
    ffmpeg -hide_banner -i $file.fullname -af volumedetect -vn -sn -dn -f null NUL 2>silences.tmp
    $mean_volume = @(get-content silences.tmp | 
      # assumes ffmpeg output format "[*volumedetect* @ <something>] mean_volume: <number> dB"
      Where-Object {$_ -like "*volumedetect*mean_volume*"} | 
      ForEach-Object{$_.split(":")[1].replace(" ","").replace("dB","")}
    )
    
    Write-host ("Detecting silence in " + $file.name + " using mean volume ${mean_volume}dB as threshold...")
    ffmpeg -hide_banner -i $file.fullname -af "silencedetect=n=${mean_volume}dB:d=0.5" -vn -sn -dn -f null - 2>silences.tmp

    $starts = @(get-content silences.tmp | 
      # assumes ffmpeg output format "[silencedetect @ <something>] silence_start: <seconds>"
      Where-Object {$_ -like "*silencedetect*silence_start*"} | 
      ForEach-Object{$_.split(":")[1].replace(" ","")} |
      ForEach-Object{([double]$_ + 0.125).toString("0.####").replace(",",".")}
    )
    $ends = @(get-content silences.tmp | 
      # assumes ffmpeg output format "[silencedetect @ <something>] silence_end: <seconds> | silence_duration: <seconds>"
      Where-Object {$_ -like "*silencedetect*silence_end*"} | 
      ForEach-Object{$_.split(":")[1].split("|")[0].replace(" ","")} |
      ForEach-Object{([double]$_ - 0.125).toString("0.####").replace(",",".")}
    )
    
    if ($starts.length -gt 0) {
      $removes = @(for($i = 0; $i -lt $starts.length; $i += 1) {
        "between(t," + $starts[$i] + "," + $ends[$i] + ")"
      }) -join "-"
      
      
      "select='1-" + $removes + "', setpts=N/FRAME_RATE/TB" | set-content $videoFilterFile
      "aselect='1-" + $removes + "', asetpts=N/SR/TB" | set-content $audioFilterFile
      
      $outputfile = get-OutputFileName $file
      
      ffmpeg -hide_banner -i $file.fullname -filter_script:v $videoFilterFile -filter_script:a $audioFilterFile $outputfile
    }

    if(test-path silences.tmp){ remove-item silences.tmp }
    if(test-path $videoFilterFile) { remove-item $videoFilterFile }
    if(test-path $audioFilterFile) { remove-item $audioFilterFile }
    
    $alreadyProcessedFiles.add($file.fullname, $true)
    $files = get-mp4s $alreadyProcessedFiles
  }

}