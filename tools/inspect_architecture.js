const fs = require('fs');
const path = require('path');

function walk(dir) {
  let results = [];
  if (!fs.existsSync(dir)) return results;
  const list = fs.readdirSync(dir);
  list.forEach(file => {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(walk(fullPath));
    } else if (file.endsWith('.dart') || file.endsWith('.js') || file.endsWith('.py')) {
      results.push(fullPath);
    }
  });
  return results;
}

const dartFiles = walk('lib');
const colRegex = /\.collection\(['"]([^'"]+)['"]\)/g;
const storageRegex = /(?:FirebaseStorage\.instance\.ref|refFromURL|\.ref)\(([^)]+)\)/g;

const collections = new Map();
const storageRefs = new Map();

dartFiles.forEach(f => {
  const content = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = colRegex.exec(content)) !== null) {
    const col = m[1];
    if (!collections.has(col)) collections.set(col, []);
    collections.get(col).push(f);
  }
  while ((m = storageRegex.exec(content)) !== null) {
    const s = m[1].trim();
    if (!storageRefs.has(s)) storageRefs.set(s, []);
    storageRefs.get(s).push(f);
  }
});

console.log('=== FIRESTORE COLLECTIONS USED IN LIB ===');
for (const [col, files] of collections.entries()) {
  console.log(`- ${col} (${files.length} references, e.g. ${files[0]})`);
}

console.log('\n=== STORAGE REFS USED IN LIB ===');
for (const [ref, files] of storageRefs.entries()) {
  console.log(`- ${ref} (in ${files[0]})`);
}
