create table sow_assumptions
(
    assumption_id    integer generated always as identity
        primary key,
    agreement_id     integer not null
        references agreements
            on delete cascade,
    category         varchar(100),
    text             text    not null,
    risk_if_breached text,
    created_at       timestamp with time zone default now(),
    updated_at       timestamp with time zone default now()
);

create table sow_change_requests
(
    cr_id            integer generated always as identity
        primary key,
    agreement_id     integer                                             not null
        references agreements
            on delete cascade,
    title            varchar(255)                                        not null,
    description      text,
    scope_delta      text,
    price_delta      numeric(14, 2),
    time_delta_days  integer,
    status           cr_status                default 'draft'::cr_status not null,
    submitted_by     varchar(255),
    approved_by      varchar(255),
    approved_at      timestamp with time zone,
    supersedes_cr_id integer
                                                                         references sow_change_requests
                                                                             on delete set null,
    created_at       timestamp with time zone default now(),
    updated_at       timestamp with time zone default now()
)
;

create table sow_deliverables
(
    deliverable_id   integer generated always as identity
        primary key,
    agreement_id     integer      not null
        references agreements
            on delete cascade,
    title            varchar(255) not null,
    description      text,
    artifact_type    varchar(100),
    due_date         date,
    acceptance_notes text,
    created_at       timestamp with time zone default now(),
    updated_at       timestamp with time zone default now()
);

create table sow_expenses_policy
(
    expenses_id          integer generated always as identity
        primary key,
    agreement_id         integer not null
        references agreements
            on delete cascade,
    reimbursable         boolean                  default false,
    preapproval_required boolean                  default false,
    caps_notes           text,
    non_reimbursable     text,
    created_at           timestamp with time zone default now(),
    updated_at           timestamp with time zone default now()
);

create table sow_invoicing_terms
(
    invoicing_id     integer generated always as identity
        primary key,
    agreement_id     integer         not null
        references agreements
            on delete cascade,
    billing_trigger  billing_trigger not null,
    frequency        varchar(50),
    net_terms_days   integer,
    late_fee_percent numeric(5, 2),
    invoice_notes    text,
    created_at       timestamp with time zone default now(),
    updated_at       timestamp with time zone default now()
);


create table sow_milestones
(
    milestone_id integer generated always as identity
        primary key,
    agreement_id integer      not null
        references agreements
            on delete cascade,
    title        varchar(255) not null,
    description  text,
    target_date  date,
    depends_on   integer
                              references sow_milestones
                                  on delete set null,
    created_at   timestamp with time zone default now(),
    updated_at   timestamp with time zone default now()
);

create table sow_pricing_schedules
(
    pricing_id          integer generated always as identity
        primary key,
    agreement_id        integer       not null
        references agreements
            on delete cascade,
    pricing_model       pricing_model not null,
    currency            varchar(10)              default 'USD'::character varying,
    fixed_total         numeric(14, 2),
    not_to_exceed_total numeric(14, 2),
    usage_unit          varchar(64),
    usage_rate          numeric(14, 6),
    notes               text,
    created_at          timestamp with time zone default now(),
    updated_at          timestamp with time zone default now()
);

create table sow_rate_cards
(
    rate_card_id    integer generated always as identity
        primary key,
    agreement_id    integer        not null
        references agreements
            on delete cascade,
    role            varchar(100)   not null,
    hourly_rate     numeric(12, 2) not null,
    currency        varchar(10)              default 'USD'::character varying,
    effective_start date           not null,
    effective_end   date,
    created_at      timestamp with time zone default now(),
    updated_at      timestamp with time zone default now()
);

create table staging_uploads
(
    staging_upload_id     integer generated always as identity
        primary key,
    status                staging_status           default 'uploaded'::staging_status not null,
    scan_status           scan_status              default 'skipped'::scan_status     not null,
    source_hash           varchar(64)                                                 not null,
    storage_provider      varchar(32)              default 'local'::character varying not null,
    storage_bucket        varchar(128),
    storage_key           varchar(512)                                                not null,
    content_type_detected varchar(128)                                                not null
        constraint chk_staging_mime_allowed
            check ((content_type_detected)::text = ANY
                   ((ARRAY ['application/pdf'::character varying, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::character varying, 'text/plain'::character varying])::text[])),
    original_filename     varchar(255)                                                not null,
    byte_size             bigint                                                      not null
        constraint staging_uploads_byte_size_check
            check (byte_size >= 0),
    uploader_user_id      integer,
    rejection_reason      text,
    metadata              jsonb                    default '{}'::jsonb                not null
        constraint chk_metadata_page_count_numeric
            check (((metadata ? 'page_count'::text) IS FALSE) OR
                   (jsonb_typeof((metadata -> 'page_count'::text)) = 'number'::text)),
    inserted_at           timestamp with time zone default now()                      not null,
    updated_at            timestamp with time zone default now()                      not null
);

