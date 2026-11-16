import {mkdirSync,readFileSync,writeFileSync,copyFileSync} from 'node:fs';
import {dirname,resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';

// Explicit runtime dependency graph: never upload .env, secret directories,
// credentials, test/business backups, local models or administrator utilities.
export function prepareCloudSource(output){
  const root=dirname(fileURLToPath(import.meta.url)),stage=resolve(output);
  mkdirSync(stage); // Refuse an existing directory rather than replace content.
  const files=new Set();
  function copy(name){
    if(files.has(name))return;
    if(!/^[a-z0-9_]+\.mjs$/.test(name)||name.endsWith('.test.mjs'))throw Error('Invalid runtime dependency');
    const code=readFileSync(join(root,name),'utf8');files.add(name);writeFileSync(join(stage,name),code);
    for(const m of code.matchAll(/(?:from\s*|import\s*\(\s*)['"]\.\/([^'"]+\.mjs)['"]/g))copy(m[1]);
  }
  copy('server.mjs');
  for(const name of ['package.json','package-lock.json','Dockerfile','.dockerignore'])copyFileSync(join(root,name),join(stage,name));
  copyFileSync(join(root,'../assets/images/accessory-catalogue.json'),join(stage,'accessory-catalogue.json'));
  copyFileSync(join(root,'../assets/support/guide.json'),join(stage,'guide.json'));
  return [...files].sort();
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  if(!process.argv[2])throw Error('Usage: node prepare_cloud_source.mjs NEW_OUTPUT_DIRECTORY');
  console.log('Prepared',prepareCloudSource(process.argv[2]).length,'runtime modules.');
}
