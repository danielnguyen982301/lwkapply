"""
Unit tests for app.schemas.document.

DocumentCreate is intentionally not user-facing (see schema module
docstring) - upload metadata comes from the multipart upload endpoint,
not a JSON body - so these tests cover DocumentUpdate and confirm
DocumentRead never exposes a raw file_url.
"""

from app.models.document import DocumentType
from app.schemas.document import DocumentRead, DocumentUpdate


class TestDocumentUpdate:
    def test_file_type_can_be_updated(self):
        update = DocumentUpdate(file_type=DocumentType.RESUME)
        assert update.file_type == DocumentType.RESUME

    def test_empty_update_is_valid(self):
        update = DocumentUpdate()
        assert update.file_type is None


class TestDocumentReadShape:
    def test_file_url_is_not_a_field(self):
        # Guards against someone accidentally re-adding file_url to
        # DocumentRead later and silently exposing the permanent S3 key.
        assert "file_url" not in DocumentRead.model_fields