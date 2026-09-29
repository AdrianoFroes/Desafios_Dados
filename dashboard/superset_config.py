import os

from celery.schedules import crontab

SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]

# Metadados no PostgreSQL: web, worker e beat gravam ao mesmo tempo, e com SQLite
# o worker falha ao registrar a execução do alerta (report_execution_log).
SQLALCHEMY_DATABASE_URI = os.environ.get("SUPERSET_META_URI", "sqlite:////app/superset_home/superset.db")

# Habilitar acesso público e iframe embutido
# Anônimo só lê: Public copia o Gamma (sem SQL Lab nem administração) e recebe,
# em setup_superset_internal.py, acesso apenas aos datasets agregados do dashboard.
AUTH_ROLE_PUBLIC = "Public"
PUBLIC_ROLE_LIKE = "Gamma"

# RF18: filtros nativos, filtro cruzado e alertas
FEATURE_FLAGS = {
    "EMBEDDED_SUPERSET": True,
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "ALERT_REPORTS": True,
}

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")


class CeleryConfig:
    broker_url = f"redis://{REDIS_HOST}:6379/0"
    result_backend = f"redis://{REDIS_HOST}:6379/0"
    imports = ("superset.sql_lab", "superset.tasks.scheduler")
    worker_prefetch_multiplier = 1
    task_acks_late = False
    beat_schedule = {
        "reports.scheduler": {
            "task": "reports.scheduler",
            "schedule": crontab(minute="*", hour="*"),
        },
        "reports.prune_log": {
            "task": "reports.prune_log",
            "schedule": crontab(minute=0, hour=0),
        },
    }


CELERY_CONFIG = CeleryConfig

# E-mail do alerta: servidor SMTP fictício (Mailpit, http://localhost:8025)
SMTP_HOST = os.environ.get("SMTP_HOST", "mailpit")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "1025"))
SMTP_STARTTLS = False
SMTP_SSL = False
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
SMTP_MAIL_FROM = os.environ.get("SMTP_MAIL_FROM", "superset@ficticio.edu.br")
EMAIL_NOTIFICATIONS = True
ALERT_REPORTS_NOTIFICATION_DRY_RUN = False
WEBDRIVER_BASEURL = "http://superset:8088/"
WEBDRIVER_BASEURL_USER_FRIENDLY = "http://localhost:8088/"

# Desativar restrições de CSP/Talisman para permitir iframe
TALISMAN_ENABLED = False
HTTP_HEADERS = {}

# Habilitar CORS
ENABLE_CORS = True
CORS_OPTIONS = {
    "supports_credentials": True,
    "allow_headers": ["*"],
    "resources": ["*"],
    "origins": ["*"]
}

# Configuração de cookies para permitir iframe
SESSION_COOKIE_SAMESITE = "None"
SESSION_COOKIE_SECURE = False
