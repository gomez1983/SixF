"""Isolated FFmpeg measurements, matching production remux flags; not app heap profiling."""
import json, subprocess, time, pathlib, psutil
root = pathlib.Path('build/audit-profile')
root.mkdir(parents=True, exist_ok=True)
source = root / '1080p.mkv'
subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i',
    'testsrc2=size=1920x1080:rate=30:duration=12','-f','lavfi','-i','sine=duration=12',
    '-c:v','libx264','-preset','veryfast','-g','300','-c:a','aac',str(source)],check=True)
rows=[]
for label,seek in [('copy',0),('seek',3.25)]:
    args=['ffmpeg','-v','error','-y','-copyts','-start_at_zero']
    if seek: args+=['-ss',str(seek)]
    args+=['-i',str(source),'-map','0:v:0?','-map','0:a:0?']
    args+=['-c:v','libx264','-preset','ultrafast','-tune','zerolatency','-g','30',
           '-sc_threshold','0','-crf','23','-pix_fmt','yuv420p'] if seek else ['-c:v','copy']
    args+=['-c:a','aac','-b:a','192k','-ac','2','-output_ts_offset',str(-seek),
        '-avoid_negative_ts','disabled','-use_editlist','1','-movflags',
        'frag_keyframe+delay_moov+default_base_moof','-frag_duration','1000000',
        '-flush_packets','1','-f','mp4','pipe:1']
    target=root/f'{label}.mp4'
    start=time.perf_counter(); peak=cpu=0
    with target.open('wb') as output:
        proc=subprocess.Popen(args,stdout=output,stderr=subprocess.PIPE)
        observed=psutil.Process(proc.pid)
        while proc.poll() is None:
            try:
                peak=max(peak,observed.memory_info().rss)
                times=observed.cpu_times();cpu=max(cpu,times.user+times.system)
            except psutil.NoSuchProcess: pass
            time.sleep(.02)
        errors=proc.stderr.read().decode(errors='replace')
    if proc.returncode: raise RuntimeError(errors)
    elapsed=time.perf_counter()-start
    rows.append({'case':label,'source_seconds':12-seek,'elapsed_seconds':round(elapsed,3),
        'sampled_cpu_seconds':round(cpu,3),'peak_rss_mib':round(peak/2**20,1),
        'output_mib':round(target.stat().st_size/2**20,2), 'exit_code':proc.returncode})
result={'fixture':'synthetic 1080p30, H264+AAC, 12s','scope':'FFmpeg subprocess only, sampled every20ms',
        'measurements':rows}
pathlib.Path('docs/security/audits/support/2026-11-04-profile.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
