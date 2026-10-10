import nodemailer from 'nodemailer';
import type { Config } from './config.ts';
import { SesMailer } from './ses.ts';

export interface Mail {
  to: string;
  subject: string;
  text: string;
}

export interface Mailer {
  send(mail: Mail): Promise<void>;
}

/** DEV/test: logs mail and keeps it in memory. */
export class ConsoleMailer implements Mailer {
  readonly outbox: Mail[] = [];
  private readonly log: (msg: string) => void;
  constructor(log: (msg: string) => void = console.log) {
    this.log = log;
  }
  async send(mail: Mail): Promise<void> {
    this.outbox.push(mail);
    this.log(`📧 to=${mail.to} subject="${mail.subject}"\n${mail.text}`);
  }
}

export class SmtpMailer implements Mailer {
  private readonly transport;
  private readonly from: string;
  constructor(url: string, from: string) {
    this.from = from;
    this.transport = nodemailer.createTransport(url);
  }
  async send(mail: Mail): Promise<void> {
    await this.transport.sendMail({ from: this.from, ...mail });
  }
}

export const createMailer = (c: Config): Mailer =>
  c.mail.transport === 'ses'
    ? new SesMailer(c.mail.ses!, c.mail.from)
    : c.mail.transport === 'smtp'
      ? new SmtpMailer(c.mail.smtpUrl!, c.mail.from)
      : new ConsoleMailer();
