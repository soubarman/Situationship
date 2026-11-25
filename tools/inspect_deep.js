const fs = require('fs');

function inspectReferences(pattern, title) {
  console.log(`\n=== ${title} ===`);
  const lines = [];
  const walk = (dir) => {
    fs.readdirSync(dir).forEach(file => {
      const p = `${dir}/${file}`;
      if (fs.statSync(p).isDirectory()) walk(p);
      else if (file.endsWith('.dart')) {
        const text = fs.readFileSync(p, 'utf8');
        const fileLines = text.split('\n');
        fileLines.forEach((l, idx) => {
          if (pattern.test(l)) {
            lines.push(`${p}:${idx + 1}: ${l.trim()}`);
          }
        });
      }
    });
  };
  walk('lib');
  lines.slice(0, 15).forEach(l => console.log(l));
}

inspectReferences(/\.collection\(['"]messages['"]\)/, "COLLECTION: messages");
inspectReferences(/\.collection\(['"]bids['"]\)/, "COLLECTION: bids");
inspectReferences(/chats\/.*\/|ref\(.*chats/, "STORAGE: chats attachments");
inspectReferences(/ref\(.*verifications/, "STORAGE: verifications");
inspectReferences(/\.collection\(['"]notifications['"]\)/, "COLLECTION: notifications");
inspectReferences(/\.collection\(['"]profile_views['"]\)/, "COLLECTION: profile_views");
