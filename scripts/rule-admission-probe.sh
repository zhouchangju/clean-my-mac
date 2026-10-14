#!/bin/sh
# Every mutation is inside a newly created 0700 fixture. No HOME override.
set -eu
python3 - <<'PY'
import os, pathlib, tempfile, subprocess, json, hashlib, time, stat, shutil
repo=pathlib.Path.cwd()
out=repo/'.local/verification/rule-admission'; out.mkdir(parents=True,exist_ok=True)
root=pathlib.Path(tempfile.mkdtemp(prefix='lmc-rule-admission-')); root.chmod(0o700)
(root/'.lmc-fixture-marker').write_text('rule-admission-v1\n')
identity=(root.stat().st_dev,root.stat().st_ino)
report={'fixture':str(root),'rootIdentity':identity,'rootMode':oct(stat.S_IMODE(root.stat().st_mode)),'commands':[],'facts':{}}
def guard(p):
 assert root.exists() and not root.is_symlink() and (root.stat().st_dev,root.stat().st_ino)==identity
 assert (root/'.lmc-fixture-marker').read_text()=='rule-admission-v1\n'
 assert p.is_relative_to(root) and not p.is_symlink()
def run(args,name,env=None):
 p=subprocess.run(args,cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env)
 (out/(name+'.log')).write_text(p.stdout)
 report['commands'].append({'name':name,'args':args,'exitCode':p.returncode,'log':str(out/(name+'.log'))})
 if p.returncode: raise RuntimeError(name+' failed')
 return p.stdout
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def leaves(p):return sorted(x for x in p.rglob('*') if x.is_file() and not x.is_symlink())
try:
 run(['xcodebuild','-version'],'xcode-version'); run(['npm','--version'],'npm-version'); run(['node','--version'],'node-version')
 proj=root/'Probe.xcodeproj'; proj.mkdir(); (root/'main.c').write_text('#include <stdio.h>\nint main(void){puts("LMC fixture build works");return 0;}\n')
 (proj/'project.pbxproj').write_text('''// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
 A00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000008; compatibilityVersion = "Xcode 14.0"; mainGroup = A00000000000000000000002; productRefGroup = A00000000000000000000003; projectDirPath = ""; targets = (A00000000000000000000004);};
 A00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000005,A00000000000000000000003); sourceTree = "<group>";};
 A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000006); name = Products; sourceTree = "<group>";};
 A00000000000000000000004 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000009; buildPhases = (A00000000000000000000007); buildRules = (); dependencies = (); name = Probe; productName = Probe; productReference = A00000000000000000000006; productType = "com.apple.product-type.tool";};
 A00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; path = main.c; sourceTree = "<group>";};
 A00000000000000000000006 = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; path = Probe; sourceTree = BUILT_PRODUCTS_DIR;};
 A00000000000000000000007 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000000A); runOnlyForDeploymentPostprocessing = 0;};
 A0000000000000000000000A = {isa = PBXBuildFile; fileRef = A00000000000000000000005;};
 A00000000000000000000008 = {isa = XCConfigurationList; buildConfigurations = (A0000000000000000000000B); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;};
 A00000000000000000000009 = {isa = XCConfigurationList; buildConfigurations = (A0000000000000000000000C); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;};
 A0000000000000000000000B = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx;}; name = Debug;};
 A0000000000000000000000C = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; CODE_SIGNING_ALLOWED = NO; MACOSX_DEPLOYMENT_TARGET = 14.0;}; name = Debug;};
 }; rootObject = A00000000000000000000001; }
''')
 scheme=proj/'xcshareddata/xcschemes'; scheme.mkdir(parents=True)
 (scheme/'Probe.xcscheme').write_text('''<?xml version="1.0"?><Scheme version="1.3"><BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForRunning="YES" buildForTesting="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000004" BuildableName="Probe" BlueprintName="Probe" ReferencedContainer="container:Probe.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction></Scheme>''')
 derived=root/'profile/Library/Developer/Xcode/DerivedData/Probe-fixture'
 build=['xcodebuild','-project',str(proj),'-scheme','Probe','-derivedDataPath',str(derived),'-configuration','Debug','-disableAutomaticPackageResolution','CODE_SIGNING_ALLOWED=NO','build']
 run(build,'xcode-build-before'); run([str(derived/'Build/Products/Debug/Probe')],'xcode-run-before')
 inter=derived/'Build/Intermediates.noindex'; files=leaves(inter); assert files
 chosen=next(p for p in files if p.suffix=='.o'); before=sha(chosen)
 stage=root/'staging'; stage.mkdir(); guard(chosen); saved=stage/'xcode-object'; chosen.rename(saved)
 run(build,'xcode-build-after'); run([str(derived/'Build/Products/Debug/Probe')],'xcode-run-after')
 report['facts']['xcode']={'ordinaryLeaf':str(chosen.relative_to(root)),'beforeSHA256':before,'regenerated':chosen.exists(),'afterSHA256':sha(chosen),'sourceSHA256':sha(root/'main.c'),'intermediatesFileCount':len(files),'originalStaged':saved.exists()}
 # Recovery conflict never overwrites the regenerated object. Restore only to fresh fixture path.
 conflict=chosen.exists(); restore=root/'restored-original.o'; guard(restore); saved.rename(restore)
 report['facts']['xcode']['restoreConflictRefused']=conflict
 report['facts']['xcode']['restoredSHA256']=sha(restore)
 npmroot=pathlib.Path(os.path.realpath(shutil.which('npm'))).parent.parent
 cacache=npmroot/'node_modules/cacache'; assert (cacache/'package.json').exists()
 cache=root/'profile/npm-cache/_cacache'; cache.mkdir(parents=True)
 js=root/'npm-probe.cjs'; js.write_text('''const fs=require('fs/promises'); const path=require('path'); const cc=require(process.argv[2]); const tmp=require(path.join(process.argv[2],'lib/util/tmp.js'));\n(async()=>{const cache=process.argv[3]; const dir=await tmp.mkdir(cache,{tmpPrefix:'lmc-fixture'}); const file=path.join(dir,'ordinary-artifact'); await fs.writeFile(file,'LMC owned temporary fixture'); const old=new Date(Date.now()-8*24*3600*1000); await fs.utimes(file,old,old); await cc.put(cache,'lmc-owned-key','LMC cache value'); const got=await cc.get(cache,'lmc-owned-key'); console.log(JSON.stringify({tmpFile:file,value:got.data.toString(),cacacheVersion:require(path.join(process.argv[2],'package.json')).version}));})().catch(e=>{console.error(e);process.exit(1)});''')
 one=json.loads(run(['node',str(js),str(cacache),str(cache)],'npm-cacache-before'))
 leaf=pathlib.Path(one['tmpFile']); guard(leaf); oldhash=sha(leaf); staged=stage/'npm-tmp'; leaf.rename(staged)
 two=json.loads(run(['node',str(js),str(cacache),str(cache)],'npm-cacache-after'))
 regenerated=pathlib.Path(two['tmpFile']); assert sha(regenerated)==oldhash
 restored=leaf; guard(restored); assert not restored.exists(); staged.rename(restored)
 report['facts']['npm']={'cacacheVersion':one['cacacheVersion'],'tmpBefore':str(leaf.relative_to(root)),'tmpAfter':str(regenerated.relative_to(root)),'regeneratedSamePayload':True,'cacheReadAfter':two['value'],'restoredSHA256':sha(restored),'ageSeconds':int(time.time()-restored.stat().st_mtime),'implementationRoot':str(cacache),'limitation':'tmp leaf payload is a fixture generated using installed cacache.tmp.mkdir, not a retained artifact from interrupted npm install; no dependencies installed'}
 report['status']='PASS_FOR_BOUNDED_REBUILD_ONLY_NOT_ADMISSION'
except Exception as e:
 report['status']='FAIL';report['error']=str(e)
finally:
 (out/'probe-result.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(report,indent=2))
 # Leave owned fixture for independent review; do not recursively remove anything.
PY
