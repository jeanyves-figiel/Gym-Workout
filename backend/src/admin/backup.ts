import { resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { backupDirFor, backupNow, inspectCopy, listBackups, stageRestore } from '../backup.ts';

// CLI (#310), run on the Fly machine by the "Fly backups" workflow:
//   node src/admin/backup.ts list | now | verify <file> | stage-restore <file>
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [cmd, file] = process.argv.slice(2);
  const path = process.env.DB_PATH ?? '/data/app.db';
  const dir = backupDirFor(path);
  const keep = Number(process.env.BACKUP_KEEP_DAYS ?? 7);
  const out = (v: unknown) => console.log(JSON.stringify(v, null, 2));
  if (cmd === 'list') out({ dir, backups: listBackups(dir), live: inspectCopy(path) });
  else if (cmd === 'now') {
    const db = new DatabaseSync(path);
    db.exec('PRAGMA busy_timeout = 5000;');
    out(backupNow(db, dir, { keep }));
    db.close();
  } else if (cmd === 'verify' && file) out({ file, ...inspectCopy(resolve(dir, file)) });
  else if (cmd === 'stage-restore' && file) {
    stageRestore(dir, file, path);
    out({ staged: file, next: 'restart the machine to swap it in; the current database is kept in backups/pre-restore-*.db' });
  } else {
    console.error('usage: backup.ts list | now | verify <file> | stage-restore <file>');
    process.exit(2);
  }
}
