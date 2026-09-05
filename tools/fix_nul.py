p='tools/gen_changan_tiles.py'
data=open(p,'rb').read()
esc=b'\x00'
data=data.replace(b'\x00', esc)
open(p,'wb').write(data)
print('remaining NUL:', open(p,'rb').read().count(b'\x00'))
