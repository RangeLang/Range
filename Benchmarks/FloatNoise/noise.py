def fade(v): return v*v*v*(v*(v*6.0-15.0)+10.0)
def noise(x,y,z):
    xy,yz,zx=x*y,y*z,z*x; u,v,w=fade(x),fade(y),fade(z)
    first,second,third=xy+yz,yz+zx,zx+xy
    return (first*(1.0-u)+second*u)*(1.0-w)+third*w+v
total=0.0; x=0.37
for _ in range(1000000): total += noise(x,0.61,0.23); x += 0.00001
raise SystemExit(1 if total > 0.0 else 0)
