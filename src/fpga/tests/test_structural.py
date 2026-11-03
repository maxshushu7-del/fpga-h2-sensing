from pathlib import Path
import re, subprocess,sys
r=Path(__file__).resolve().parents[1]
# Balanced delimiters, after stripping comments and quoted strings.
for f in list((r/'rtl/network').glob('*.v')) + [r/'rtl/servo/laser_lock_hw_udp_only_top.v']:
    s=f.read_text()
    s=re.sub(r'/\*.*?\*/','',s, flags=re.S)
    s=re.sub(r'//[^\n]*','',s)
    s=re.sub(r'"(?:\\.|[^"\\])*"','""',s)
    for o,c in [('(',')'),('[',']'),('{','}')]:
        n=0
        for ch in s:
            if ch==o:n+=1
            if ch==c:n-=1
            assert n>=0,(f.name,o,c,'underflow')
        assert n==0,(f.name,o,c,n)
    assert len(re.findall(r'\bmodule\b',s))==len(re.findall(r'\bendmodule\b',s)),f.name
print('PASS new module delimiter and definition checks')
