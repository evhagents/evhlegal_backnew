# EVH Legal Chat

## Step 6: Confidence-aware mapping

This step introduces evidence-backed mapping from extracted candidates to canonical fields.

- Thresholds are configurable in `config/config.exs` under `Evhlegalchat.Mapping.Config`:
  - `auto_commit_threshold` (default 0.80): candidates at/above auto-apply
  - `review_threshold` (default 0.60): candidates below this are rejected; in-between open a review task
  - `allow_downgrade` false: do not overwrite approved fields with lower confidence
  - `prefer_newer_equal_conf` true: on tie, prefer newer

- New tables: `extracted_facts`, `review_tasks`, `field_audit` with enums `mapping_status`, `review_state` and updated_at triggers.

- Public API to submit candidates without committing:

```elixir
Evhlegalchat.Mapping.capture_fact(%{
  agreement_id: 27,
  target_table: "agreements",
  target_pk_name: "agreement_id",
  target_pk_value: 27,
  target_column: "term_length_months",
  raw_value: "two (2) years",
  normalized_value: "24 months",
  normalized_numeric: 24,
  normalized_unit: "months",
  evidence_clause_id: 1234,
  evidence_start_char: 809,
  evidence_end_char: 855,
  evidence_start_page: 3,
  evidence_end_page: 3,
  confidence: 0.87,
  extractor: "NDA.Keys.term_duration",
  extractor_version: "1.3.0",
  reason: "regex:term_duration v2"
})
```

Approvals can be performed from IEx by updating a proposed fact to `:applied` via the mapper, which will write `field_audit` and resolve the review task.

Run a JSON feed and worker:

```bash
mix mapping:apply --agreement 27 --facts priv/samples/facts_27.json
```

A Phoenix LiveView application for legal document analysis and chat assistance, powered by OpenRouter AI.

## Features

- **Legal Document Analysis**: Upload and analyze NDAs, joinders, and other legal documents
- **AI-Powered Chat**: Ask questions about legal terms, notice periods, governing law, and more
- **Modern UI**: Built with Phoenix LiveView and Tailwind CSS
- **Real-time Updates**: Live chat interface with streaming responses
- **File Upload Pipeline**: Robust staging system with deduplication and virus scanning

## Setup

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL 12+
- Node.js 18+ (for assets)

### Installation

1. **Clone and install dependencies:**
   ```bash
   git clone <repository-url>
   cd evhlegalchat
   mix setup
   ```

2. **Set up environment variables:**
   
   Create a `.env` file in the project root:
   ```bash
   OPENROUTER_API_KEY=your_openrouter_api_key_here
   ```

   Or set the environment variable directly:
   ```bash
   # Windows PowerShell
   $env:OPENROUTER_API_KEY="your_api_key_here"
   
   # Linux/macOS
   export OPENROUTER_API_KEY="your_api_key_here"
   ```

3. **Start the development server:**
   ```bash
   mix phx.server
   ```

4. **Visit the application:**
   Open [http://localhost:4000](http://localhost:4000) in your browser.

5. **Access the staging upload interface:**
   Navigate to [http://localhost:4000/staging/uploads](http://localhost:4000/staging/uploads) to upload and manage files.

## Configuration

### OpenRouter API

The application uses OpenRouter for AI chat functionality. You'll need to:

1. Sign up at [OpenRouter](https://openrouter.ai/)
2. Get your API key
3. Set the `OPENROUTER_API_KEY` environment variable

### Database

The application uses PostgreSQL. Make sure PostgreSQL is running and accessible with the credentials in `config/dev.exs`.

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
mix precommit  # Runs compile, format, and tests
```

## File Upload Pipeline

The application includes a comprehensive multi-step pipeline for processing uploaded documents.

### Step 1: Intake & Staging

Document intake and secure storage with deduplication.

### Supported File Types
- **PDF** (.pdf) - Legal documents, contracts, etc.
- **DOCX** (.docx) - Microsoft Word documents
- **TXT** (.txt) - Plain text files

### Storage Configuration

Files are stored locally on the filesystem with atomic operations:

```bash
# Set custom storage root (default: priv/storage)
export STORAGE_ROOT=/path/to/your/storage

# Example paths for production
export STORAGE_ROOT=/var/lib/evhlegalchat/storage
```

### Manual File Staging

Use the mix task to stage files manually:

```bash
# Stage a PDF file
mix ingest:stage --path /path/to/document.pdf

# Stage a DOCX file
mix ingest:stage --path test/fixtures/sample.docx
```

### Background Processing

Files are processed through Oban background jobs:

```bash
# Check job status (requires database access)
# The staging_uploads table tracks processing status:
# - uploaded → ready_for_extraction → extracting → extracted
```

### Deduplication

Files are deduplicated based on SHA256 hash:
- Identical files (even with different names) map to the same staging record
- Duplicate uploads return the existing record without reprocessing
- Storage space is preserved through content addressing

### Step 2: Text Extraction Pipeline

Text extraction and content normalization with comprehensive artifact generation.

#### Prerequisites (Required Tools)

Install the following tools for full extraction capabilities:

**Ubuntu/Debian:**
```bash
# PDF processing
sudo apt-get install -y poppler-utils  # pdftotext, pdftoppm, pdfinfo
sudo apt-get install -y tesseract-ocr   # OCR capabilities

# DOCX processing  
sudo apt-get install -y pandoc          # Primary DOCX extraction
sudo apt-get install -y libreoffice     # Fallback DOCX extraction

# Language detection (handled by Elixir)
# No additional packages needed
```

**macOS:**
```bash
# Install via Homebrew
brew install poppler   # pdftotext, pdftoppm, pdfinfo
brew install tesseract # OCR capabilities
brew install pandoc    # DOCX extraction
brew install libreoffice # Fallback DOCX extraction
```

**Windows:**
```powershell
# Install via Chocolatey
choco install poppler tesseract pandoc libreoffice

# Or download installers:
# - Poppler for Windows: https://github.com/oschwartz10612/poppler-windows
# - Tesseract: https://github.com/UB-Mannheim/tesseract/wiki
# - Pandoc: https://pandoc.org/installing.html
# - LibreOffice: https://www.libreoffice.org/download/
```

#### Extraction Capabilities

- **PDF Processing**: Text extraction with automatic OCR for scanned documents
- **DOCX Processing**: Via Pandoc (primary) and LibreOffice (fallback)
- **TXT Processing**: Encoding detection and normalization
- **Quality Assessment**: Language detection, confidence scoring, error metrics
- **Preview Generation**: PNG thumbnails for PDF pages (optional)

#### Configuration

Set environment variables to override tool paths:

```bash
# Tool paths (optional, defaults to system PATH)
export PDFTOTEXT_PATH=/usr/bin/pdftotext
export TESSERACT_PATH=/usr/bin/tesseract
export PANDOC_PATH=/usr/bin/pandoc
export LIBREOFFICE_PATH=/usr/bin/libreoffice

# Extraction limits (optional)
export MAX_FILE_SIZE=104857600     # 100MB
export MAX_PAGES=1000
export EXTRACTION_TIMEOUT=300000   # 5 minutes
```

#### Debugging Extraction

Run extraction manually for debugging:

```bash
# Using the staging interface
curl -X POST http://localhost:4000/staging/uploads \
  -F "docs=@path/to/document.pdf"

# Using mix task (requires file already staged)
mix ingest:extract --staging-id 123

# Inspect extracted artifacts
ls -la priv/storage/staging/123/
cat priv/storage/staging/123/text/concatenated.txt
cat priv/storage/staging/123/metrics.json
```

#### Pipeline Outputs

Each extracted document generates:

```
staging/{staging_upload_id}/
├── text/
│   ├── concatenated.txt    # Full document text
│   └── pages.jsonl         # Per-page structured data
├── metrics.json            # Extraction statistics
└── previews/               # Optional page thumbnails
    ├── page-0001.png
    └── page-0002.png
```

Metrics include:
- Page count, character count, word count
- OCR usage and confidence scores
- Language detection results  
- Tool versions used for extraction

#### Observability

The extraction pipeline emits telemetry events:

- `[:ingest, :extraction, :start]` - Extraction begins
- `[:ingest, :extraction, :stop]` - Extraction completes
- `[:ingest, :extraction, :exception]` - Extraction fails
- `[:ingest, :extraction, :blocked]` - File permanently blocked (poison pill)

Monitor extraction performance and reliability through these metrics.

### Step 3: Document Segmentation Pipeline

Intelligent clause boundary detection and structured document analysis.

#### Segmentation Capabilities

- **Multi-Pattern Detection**: Numbered headings (decimal, roman, alpha), bullet points, all-caps headings, exhibit markers, signature anchors
- **Context-Aware Scoring**: Start-of-line bonuses, blank line detection, title case validation, number sequence sanity
- **Overlap Suppression**: Intelligent candidate reconciliation with configurable windows and minimum distances
- **Anomaly Detection**: Duplicate numbers, skipped sequences, unheaded blocks, page regressions, mixed numbering styles
- **Quality Gates**: Automatic review triggers for low-confidence boundaries, sparse segmentation, OCR quality issues

#### Configuration

Set segmentation parameters via environment variables:

```bash
# Segmentation thresholds (optional)
export MIN_BOUNDARY_GAP=80           # Minimum chars between boundaries
export OVERLAP_WINDOW=30            # Overlap suppression window
export ACCEPT_THRESHOLD=0.75        # Minimum score for acceptance
export REVIEW_THRESHOLD=0.40        # Score below which review is needed

# Quality gates
export MIN_BOUNDARIES_LARGE_DOC=3   # Minimum boundaries for large documents
export LARGE_DOC_PAGES=5            # Page count threshold for "large" docs
export OCR_LOW_CONF_PENALTY=0.20    # Penalty applied when OCR used
```

#### Segmentation Outputs

Each segmented document generates:

```
staging/{staging_upload_id}/
├── segments/
│   ├── clauses.jsonl              # Structured clause data
│   └── preview.json               # Review candidates (if needed)
└── segmentation_runs table        # Run metadata and metrics
```

Clause structure includes:
- Ordinal position and normalized number labels
- Character and page boundaries (start/end)
- Detected style and confidence scores
- Anomaly flags and text snippets
- Heading text and boundary confidence

#### Review Triggers

Segmentation automatically flags documents for human review when:

- **Sparse Boundaries**: Large documents (>5 pages) with <3 boundaries
- **Low Confidence**: >25% of boundaries below 0.4 confidence threshold
- **OCR Quality**: OCR used with overall confidence <0.6
- **Anomalies**: High-severity issues like page regressions or duplicate numbers

#### Observability

The segmentation pipeline emits telemetry events:

- `[:segmentation, :start]` - Segmentation begins
- `[:segmentation, :candidates]` - Candidate detection results
- `[:segmentation, :completed]` - Successful completion with metrics
- `[:segmentation, :needs_review]` - Review required with anomaly details
- `[:segmentation, :failed]` - Segmentation failure with reason

#### Debugging Segmentation

Run segmentation manually for debugging:

```bash
# Using mix task (requires file already staged and extracted)
mix ingest:segment --staging-id 123

# Inspect segmentation results
ls -la priv/storage/staging/123/segments/
cat priv/storage/staging/123/segments/clauses.jsonl

# Check segmentation runs in database
# SELECT * FROM segmentation_runs WHERE staging_upload_id = 123;
```

#### Common Issues

- **Over-segmentation**: Adjust `min_boundary_gap` and `accept_threshold`
- **Under-segmentation**: Lower `accept_threshold` or check detector patterns
- **False positives**: Review detector patterns and context scoring
- **Review loops**: Check anomaly thresholds and OCR quality settings

### Step 4: Document Promotion Pipeline

Promotes segmented documents from staging to canonical agreements with intelligent deduplication and review gating.

#### Promotion Capabilities

- **Intelligent Document Type Detection**: Analyzes clause headings to determine NDA vs SOW vs other types
- **Title Derivation**: Extracts meaningful titles from content or falls back to cleaned filenames
- **Confidence-Based Review Gating**: Automatically sets review status based on segmentation quality
- **Atomic File Promotion**: Moves artifacts from staging to canonical storage with integrity verification
- **Deduplication**: Prevents duplicate agreements by source hash, re-parents clauses to existing agreements
- **Transaction Safety**: Uses Ecto.Multi for atomic promotion with rollback on any failure

#### Document Type Detection

The system analyzes clause headings and content to determine document type:

- **NDA Detection**: Keywords like "confidential information", "non-disclosure", "trade secrets", "proprietary"
- **SOW Detection**: Keywords like "scope of work", "deliverables", "milestones", "project plan"
- **Fallback**: Defaults to NDA for ambiguous content, flags for manual review

#### Title Derivation

Titles are derived using a two-tier approach:

1. **Content-Based**: Extracts first substantial heading (5-100 chars, not just numbers)
2. **Filename Fallback**: Cleans filename separators and normalizes for display

#### Review Status Gating

Documents are automatically assigned review status based on:

- **Unreviewed**: High-quality segmentation (≥3 clauses, ≥0.7 confidence) with clear document type
- **Needs Review**: Low-quality segmentation, ambiguous document type, or title derived from filename

#### Canonical Storage Layout

Promoted agreements are organized as:

```
agreements/{agreement_id}/
├── original/
│   └── {source_hash}.{ext}        # Original uploaded file
├── text/
│   ├── concatenated.txt           # Full document text
│   └── pages.jsonl               # Page-level metadata
├── metrics.json                   # Extraction metrics
└── previews/                      # Page preview images (optional)
    ├── page-0001.png
    └── page-0002.png
```

#### Configuration

Promotion uses existing storage configuration:

```bash
# Storage root (required)
export STORAGE_ROOT="/var/lib/evhlegalchat/storage"

# Promotion thresholds (optional)
export MIN_CLAUSES_FOR_UNREVIEWED=3    # Minimum clauses for unreviewed status
export MIN_CONFIDENCE_FOR_UNREVIEWED=0.7  # Minimum confidence for unreviewed status
```

#### Observability

The promotion pipeline emits telemetry events:

- `[:promotion, :start]` - Promotion begins with staging upload ID
- `[:promotion, :completed]` - Successful promotion with agreement ID and metrics
- `[:promotion, :error]` - Promotion failure with reason and step

#### Promotion Worker

The `PromoteWorker` handles the complete promotion pipeline:

- **Advisory Locking**: Prevents concurrent promotion of the same staging upload
- **Idempotency**: Safe to re-run, detects existing agreements by source hash
- **Transaction Safety**: All-or-nothing promotion with automatic rollback
- **Artifact Verification**: Validates file integrity during promotion

#### Manual Promotion

Promote documents manually for testing or recovery:

```bash
# Using Oban job insertion
iex> Oban.insert(Evhlegalchat.Promotion.PromoteWorker.new(%{"staging_upload_id" => 123}))

# Check promotion status
# SELECT * FROM agreements WHERE source_hash = 'abc123...';
# SELECT * FROM clauses WHERE agreement_id = 456;
```

#### Common Issues

- **Missing Artifacts**: Ensure Step 2 extraction completed successfully
- **Low Quality Segmentation**: Review Step 3 segmentation results before promotion
- **File Permission Errors**: Check storage root permissions and disk space
- **Duplicate Agreements**: System automatically handles deduplication by source hash

### Developer Tools

```bash
# List staging uploads in IEx
iex> Evhlegalchat.Ingest.StagingService.list_staging_uploads()

# Get specific staging upload
iex> Evhlegalchat.Ingest.StagingService.get_staging_upload(123)

# Check storage adapter
iex> storage = Evhlegalchat.Storage.Local.new()
iex> Evhlegalchat.Storage.Local.head(storage, "key")
```

### Environment Variables

- `OPENROUTER_API_KEY`: Your OpenRouter API key (required)
- `PORT`: Server port (default: 4000)
- `PHX_HOST`: Host for the Phoenix server (default: localhost)
- `STORAGE_ROOT`: Storage directory for uploaded files (default: priv/storage)

## Production Deployment

For production deployment:

1. Set the `OPENROUTER_API_KEY` environment variable
2. Configure your database URL
3. Set `SECRET_KEY_BASE` for session encryption
4. Use `mix phx.gen.release` to generate a release

See [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for more details.

## Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [OpenRouter API](https://openrouter.ai/docs)
