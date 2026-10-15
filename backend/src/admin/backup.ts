import { resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { backupDirFor, backupNow, inspectCopy, listBackups, stageRestore } from '../backup.ts';
import { loadConfig } from '../config.ts';
import { OffsiteStore } from '../offsite.ts';

// CLI (#310), run on the Fly machine by the "Fly backups" workflow:
//   node src/admin/backup.ts list | now | verify <file> | stage-restore <file>
//   offsite-list | offsite-upload <file> | offsite-fetch <YYYY-MM-DD>  (encrypted Tigris copy, #313)
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
    const b = backupNow(db, dir, { keep });
    db.close();
    // Same as the daily job: the encrypted off-site copy follows when configured (#313).
    const c = loadConfig().offsite;
    out({ ...b, offsite: c ? await new OffsiteStore(c).upload(join(dir, b.file), b.day) : 'not configured' });
  } else if (cmd === 'verify' && file) out({ file, ...inspectCopy(resolve(dir, file)) });
  else if (cmd === 'stage-restore' && file) {
    stageRestore(dir, file, path);
    out({ staged: file, next: 'restart the machine to swap it in; the current database is kept in backups/pre-restore-*.db' });
  } else if (cmd?.startsWith('offsite-')) {
    const c = loadConfig().offsite;
    if (!c) throw new Error('off-site copy not configured (Tigris bucket secrets + BACKUP_KEY)');
    const store = new OffsiteStore(c);
    if (cmd === 'offsite-list') out({ bucket: c.bucket, copies: await store.list() });
    else if (cmd === 'offsite-upload' && file && /^app-\d{4}-\d{2}-\d{2}\.db$/.test(file)) out(await store.upload(join(dir, file), file.slice(4, 14)));
    else if (cmd === 'offsite-fetch' && file && /^\d{4}-\d{2}-\d{2}$/.test(file)) {
      // Lands as a normal backup file, so `verify` / `stage-restore` work on it.
      const dest = join(dir, `app-${file}.db`);
      await store.download(file, dest);
      out({ fetched: file, file: `app-${file}.db`, ...inspectCopy(dest) });
    } else throw new Error('usage: offsite-list | offsite-upload app-YYYY-MM-DD.db | offsite-fetch YYYY-MM-DD');
  } else {
    console.error('usage: backup.ts list | now | verify <file> | stage-restore <file> | offsite-list | offsite-upload <file> | offsite-fetch <day>');
    process.exit(2);
  }
}
