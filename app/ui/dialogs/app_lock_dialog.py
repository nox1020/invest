"""Dialogs for local app-lock password (unlock / set / change)."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QVBoxLayout,
)

from app.config import APP_NAME
from app.utils.app_lock import MIN_PASSWORD_LEN, hash_password, verify_password
from app.utils.i18n import t


class AppLockUnlockDialog(QDialog):
    """Prompt for the local app password before showing the main window."""

    def __init__(self, password_hash: str, parent=None) -> None:
        super().__init__(parent)
        self._hash = password_hash
        self.setWindowTitle(APP_NAME)
        self.setModal(True)
        self.setMinimumWidth(360)

        title = QLabel(t("app_lock_unlock_title"))
        title.setObjectName("wizardTitle")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hint = QLabel(t("app_lock_unlock_hint"))
        hint.setObjectName("mutedText")
        hint.setWordWrap(True)
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.EchoMode.Password)
        self.password.setPlaceholderText(t("app_lock_password"))
        self.password.returnPressed.connect(self._try_accept)

        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        form.addRow(t("app_lock_password"), self.password)

        buttons = QDialogButtonBox()
        enter = buttons.addButton(t("app_lock_enter"), QDialogButtonBox.ButtonRole.AcceptRole)
        quit_btn = buttons.addButton(t("app_lock_quit"), QDialogButtonBox.ButtonRole.RejectRole)
        enter.clicked.connect(self._try_accept)
        quit_btn.clicked.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.addWidget(title)
        layout.addWidget(hint)
        layout.addLayout(form)
        layout.addWidget(buttons)

    def _try_accept(self) -> None:
        if verify_password(self.password.text(), self._hash):
            self.accept()
            return
        QMessageBox.warning(self, APP_NAME, t("app_lock_wrong_password"))
        self.password.clear()
        self.password.setFocus()


class AppLockSetDialog(QDialog):
    """Set or change the local app-lock password."""

    def __init__(
        self,
        *,
        current_hash: str = "",
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._current_hash = current_hash
        self.new_hash = ""
        self.setWindowTitle(t("app_lock_set_title"))
        self.setModal(True)
        self.setMinimumWidth(400)

        if current_hash:
            subtitle = t("app_lock_change_hint")
        else:
            subtitle = t("app_lock_set_hint")

        hint = QLabel(subtitle)
        hint.setObjectName("mutedText")
        hint.setWordWrap(True)
        hint.setAlignment(Qt.AlignmentFlag.AlignRight)

        self.current = QLineEdit()
        self.current.setEchoMode(QLineEdit.EchoMode.Password)
        self.current.setPlaceholderText(t("app_lock_current_password"))

        self.new_password = QLineEdit()
        self.new_password.setEchoMode(QLineEdit.EchoMode.Password)
        self.new_password.setPlaceholderText(t("app_lock_new_password"))

        self.confirm = QLineEdit()
        self.confirm.setEchoMode(QLineEdit.EchoMode.Password)
        self.confirm.setPlaceholderText(t("app_lock_confirm_password"))

        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        if current_hash:
            form.addRow(t("app_lock_current_password"), self.current)
        form.addRow(t("app_lock_new_password"), self.new_password)
        form.addRow(t("app_lock_confirm_password"), self.confirm)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._save)
        buttons.rejected.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.addWidget(hint)
        layout.addLayout(form)
        layout.addWidget(buttons)

    def _save(self) -> None:
        if self._current_hash and not verify_password(
            self.current.text(), self._current_hash
        ):
            QMessageBox.warning(self, APP_NAME, t("app_lock_wrong_password"))
            return

        new_p = self.new_password.text()
        confirm = self.confirm.text()
        if len(new_p) < MIN_PASSWORD_LEN:
            QMessageBox.warning(self, APP_NAME, t("app_lock_password_too_short"))
            return
        if new_p != confirm:
            QMessageBox.warning(self, APP_NAME, t("app_lock_password_mismatch"))
            return

        self.new_hash = hash_password(new_p)
        self.accept()
