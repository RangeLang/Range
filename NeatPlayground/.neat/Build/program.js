const values = [1, 2, 3, 4];
let total = 0;
console.log(`[Playground.neat:5] Neat playground`);
for (const value of (values ?? [])) {
  total = total + value;
}
if (total == 10) {
  console.log(`[Playground.neat:12] sum = ${total}`);
}
else {
  console.log(`[Playground.neat:14] unexpected sum`);
}
