from pathlib import Path
import struct
import tempfile
import subprocess
temporary = tempfile.TemporaryDirectory(prefix='pv_raw16_')
proof=Path(temporary.name)
w,h=1024,768
entries=[]
def field(tag,typ,values):
 if typ==2: data=values.encode()+b'\0';n=len(data)
 elif typ in [1,7]:data=bytes(values);n=len(values)
 elif typ in [3,4]:data=struct.pack('<'+('H' if typ==3 else 'I')*len(values),*values);n=len(values)
 elif typ in [5,10]:data=b''.join(struct.pack('<'+('ii' if typ==10 else 'II'),a,b)for a,b in values);n=len(values)
 entries.append([tag,typ,n,data])
for tag,typ,vals in [(254,4,[0]),(271,2,'Reference'),(272,2,'DNG'),(274,3,[1]),(50710,1,[0,1,2]),(50711,3,[1]),(50829,4,[0,0,h,w]),(50719,4,[0,0]),(50720,4,[w,h]),(256,4,[w]),(257,4,[h]),(258,3,[16]),(259,3,[1]),(262,3,[32803]),(273,4,[0]),(277,3,[1]),(278,4,[h]),(279,4,[w*h*2]),(284,3,[1]),(33421,3,[2,2]),(33422,1,[0,1,1,2]),(50706,1,[1,4,0,0]),(50707,1,[1,3,0,0]),(50708,2,'Synthetic reference camera'),(50714,5,[(0,1)]),(50717,4,[65535]),(50721,10,[(1,1),(0,1),(0,1),(0,1),(1,1),(0,1),(0,1),(0,1),(1,1)]),(50728,5,[(1,1),(1,1),(1,1)]),(50778,3,[21])]:field(tag,typ,vals)
entries.sort();at=8+2+12*len(entries)+4;extra=bytearray();out=[]
for tag,typ,n,data in entries:
 if len(data)>4:val=struct.pack('<I',at+len(extra));extra+=data;extra+=b'\0'*(len(extra)%2)
 else:val=data.ljust(4,b'\0')
 out.append([tag,struct.pack('<HHI',tag,typ,n)+val])
pixel=at+len(extra)
for v in out:
 if v[0]==273:v[1]=struct.pack('<HHII',273,4,1,pixel)
blob=b'II'+struct.pack('<HIH',42,8,len(entries))+b''.join(v[1]for v in out)+struct.pack('<I',0)+extra
blob+=b''.join(struct.pack('<H',int(1024+x*50))for y in range(h)for x in range(w))
(proof/'synthetisch.dng').write_bytes(blob)
s=Path('macos/Runner/ImageConverter.swift').read_text().split('    // BEGIN RAW16')[1].split('    // END RAW16')[0]
(proof/'raw16_probe.swift').write_text('import Cocoa\nimport CoreImage\nimport ImageIO\nclass Probe {\n'+s+'\n}\n'+'''
let path = CommandLine.arguments[1]
guard let bytes=Probe.rawLinear16(path:path) else { fatalError("RAW16 decoder failed") }
try bytes.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
guard let source=CGImageSourceCreateWithData(bytes as CFData,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil),let data=image.dataProvider?.data else {fatalError("TIFF unreadable")}
print("bits=\\(image.bitsPerComponent) width=\\(image.width) height=\\(image.height)")
precondition(image.bitsPerComponent==16)
let count=CFDataGetLength(data)/2
let pointer=CFDataGetBytePtr(data)!
var levels=Set<UInt16>()
for i in 0..<min(count,32768) {levels.insert(UInt16(pointer[i*2]) | UInt16(pointer[i*2+1])<<8)}
print("levels=\\(levels.count)")
precondition(levels.count>256)
''')

subprocess.run(['xcrun','swiftc',str(proof/'raw16_probe.swift'),'-o',str(proof/'probe')],check=True)
subprocess.run([str(proof/'probe'),str(proof/'synthetisch.dng'),str(proof/'result.tiff')],check=True)
temporary.cleanup()
