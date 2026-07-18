function fade(v: number): number { return v*v*v*(v*(v*6.0-15.0)+10.0); }
function noise(x: number, y: number, z: number): number {
    const [xy,yz,zx]=[x*y,y*z,z*x], [u,v,w]=[fade(x),fade(y),fade(z)];
    const [first,second,third]=[xy+yz,yz+zx,zx+xy];
    return (first*(1.0-u)+second*u)*(1.0-w)+third*w+v;
}
let total=0.0, x=0.37;
for (let i=0; i<1000000; ++i) { total += noise(x,0.61,0.23); x += 0.00001; }
(globalThis as any).process.exit(total > 0.0 ? 1 : 0);
