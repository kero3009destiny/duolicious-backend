import traceback
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import os
import time

SMTP_HOST = os.environ['DUO_SMTP_HOST']
SMTP_PORT = os.environ['DUO_SMTP_PORT']
SMTP_USER = os.environ['DUO_SMTP_USER']
SMTP_PASS = os.environ['DUO_SMTP_PASS']

class Smtp:
    def __init__(self, host: str, port: int, username: str, password: str, noop_interval: int = 5):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.noop_interval = noop_interval
        self.smtp = None
        self.keep_running = threading.Event()
        self.noop_thread = threading.Thread(target=self._send_noop, daemon=True)

        self._connect()
        self._start_noop_thread()

    def _start_noop_thread(self):
        self.keep_running.set()
        if not self.noop_thread.is_alive():
            self.noop_thread.start()

    def _stop_noop_thread(self):
        self.keep_running.clear()
        if self.noop_thread.is_alive():
            self.noop_thread.join()

    def _send_noop(self):
        while self.keep_running.is_set():
            if self.smtp:
                try:
                    self.smtp.noop()
                except Exception as e:
                    print(
                        f'Error sending NOOP command:\n' +
                        traceback.format_exc()
                    )
                    self._reconnect()
            time.sleep(self.noop_interval)

    def _connect(self):
        try:
            print(f'Establishing connection to SMTP server at {self.host}')
            self.smtp = smtplib.SMTP(self.host, self.port)
            self.smtp.starttls()
            self.smtp.login(self.username, self.password)
            print(f'Connection to SMTP server at {self.host} established')
        except Exception as e:
            print(f'Failed to connect to SMTP server: {e}')

    def _reconnect(self):
        if self.smtp:
            try:
                self.smtp.quit()
            except Exception as e:
                print(f'Error while quitting SMTP connection: {e}')
        self._connect()

    def __del__(self):
        self._stop_noop_thread()
        if self.smtp:
            try:
                self.smtp.quit()
            except Exception as e:
                print(f'Error while quitting SMTP connection: {e}')

    def _try_send(
        self,
        to: str,
        subject: str,
        body: str,
        from_addr: str | None = None,
    ):
        _from_addr = from_addr or 'no-reply@duolicious.app'

        msg = MIMEMultipart('alternative')
        msg['From'] = f'Duolicious <{_from_addr}>'
        msg['To'] = to
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'html'))

        self.smtp.sendmail(
            from_addr=_from_addr,
            to_addrs=to,
            msg=msg.as_string(),
        )

    def send(self, to: str, subject: str, body: str, from_addr: str | None = None):
        try:
            self._try_send(to=to, subject=subject, body=body, from_addr=from_addr)
        except:
            print(traceback.format_exc())
            print('First attempt to send mail failed. Trying again.')
            try:
                self._connect()
                self._try_send(to=to, subject=subject, body=body, from_addr=from_addr)
            except:
                print(traceback.format_exc())
                print('Second attempt to send mail failed. Giving up.')

aws_smtp = Smtp(
    SMTP_HOST,
    SMTP_PORT,
    SMTP_USER,
    SMTP_PASS,
)
