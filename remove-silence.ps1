function removeSilenceFromMp4 () {
  $files = Get-ChildItem *.mp4 -Exclude *_removed_silence.mp4


  $videoFilterFile = "vf.tmp"
  $audioFilterFile = "af.tmp"
  # silences.tmp is used for silencedetect-output

  foreach ($file in $files){
    Write-host ("Detecting silence in " + $file.name + "...")
    ffmpeg -i $file.fullname -af silencedetect=n=-35dB:d=0.5 -f null - 2>silences.tmp

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
      
      $outputfile = $file.directoryname + [IO.Path]::DirectorySeparatorChar + $file.basename + "_removed_silence" + $file.extension
      
      ffmpeg -i $file.fullname -filter_script:v $videoFilterFile -filter_script:a $audioFilterFile $outputfile
    }

    if(test-path silences.tmp){ remove-item silences.tmp }
    if(test-path $videoFilterFile) { remove-item $videoFilterFile }
    if(test-path $audioFilterFile) { remove-item $audioFilterFile }
  }
}