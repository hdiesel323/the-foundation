-- =====================================================
-- OPENCLAW V2 BUSINESS SCHEMA
-- Tables for CRM, commerce, trading, and intelligence
-- =====================================================

-- =====================================================
-- TABLE: leads — CRM lead management with scoring
-- Feature #151
-- =====================================================
CREATE TABLE IF NOT EXISTS leads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(500) NOT NULL,
    email VARCHAR(500),
    phone VARCHAR(100),
    company VARCHAR(500),
    source VARCHAR(100) NOT NULL DEFAULT 'organic'
        CHECK (source IN ('organic', 'referral', 'paid', 'cold_outreach', 'inbound', 'partner', 'event')),
    score INTEGER DEFAULT 0 CHECK (score >= 0 AND score <= 100),
    pipeline_status VARCHAR(50) NOT NULL DEFAULT 'new'
        CHECK (pipeline_status IN ('new', 'contacted', 'qualified', 'nurturing', 'opportunity', 'converted', 'lost', 'disqualified')),
    assigned_agent VARCHAR(100) REFERENCES agents(id),
    tags TEXT[] DEFAULT '{}',
    notes TEXT,
    first_contact_at TIMESTAMPTZ,
    last_contact_at TIMESTAMPTZ,
    converted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(pipeline_status);
CREATE INDEX IF NOT EXISTS idx_leads_score ON leads(score DESC);
CREATE INDEX IF NOT EXISTS idx_leads_source ON leads(source);
CREATE INDEX IF NOT EXISTS idx_leads_assigned ON leads(assigned_agent);
CREATE INDEX IF NOT EXISTS idx_leads_email ON leads(email);

CREATE TRIGGER leads_updated_at BEFORE UPDATE ON leads
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: deals — Sales pipeline with stage tracking
-- Feature #152
-- =====================================================
CREATE TABLE IF NOT EXISTS deals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lead_id UUID REFERENCES leads(id),
    name VARCHAR(500) NOT NULL,
    value DECIMAL(15,2) NOT NULL DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD',
    stage VARCHAR(50) NOT NULL DEFAULT 'prospect'
        CHECK (stage IN ('prospect', 'discovery', 'proposal', 'negotiation', 'contract', 'closed_won', 'closed_lost')),
    probability DECIMAL(5,2) DEFAULT 0 CHECK (probability >= 0 AND probability <= 100),
    assigned_agent VARCHAR(100) REFERENCES agents(id),
    expected_close_date DATE,
    actual_close_date DATE,
    loss_reason TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_deals_stage ON deals(stage);
CREATE INDEX IF NOT EXISTS idx_deals_value ON deals(value DESC);
CREATE INDEX IF NOT EXISTS idx_deals_assigned ON deals(assigned_agent);
CREATE INDEX IF NOT EXISTS idx_deals_lead ON deals(lead_id);
CREATE INDEX IF NOT EXISTS idx_deals_probability ON deals(probability DESC);
CREATE INDEX IF NOT EXISTS idx_deals_close_date ON deals(expected_close_date);

CREATE TRIGGER deals_updated_at BEFORE UPDATE ON deals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: outreach_log — Multi-channel activity tracking
-- Feature #153
-- =====================================================
CREATE TABLE IF NOT EXISTS outreach_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lead_id UUID REFERENCES leads(id),
    deal_id UUID REFERENCES deals(id),
    agent_id VARCHAR(100) NOT NULL REFERENCES agents(id),
    activity_type VARCHAR(50) NOT NULL
        CHECK (activity_type IN ('email_sent', 'call_made', 'linkedin_sent', 'meeting_scheduled', 'proposal_sent', 'follow_up')),
    channel VARCHAR(50) NOT NULL DEFAULT 'email'
        CHECK (channel IN ('email', 'phone', 'linkedin', 'slack', 'telegram', 'in_person', 'video_call')),
    subject VARCHAR(500),
    content_summary TEXT,
    outcome VARCHAR(50) DEFAULT 'pending'
        CHECK (outcome IN ('pending', 'replied', 'no_response', 'interested', 'not_interested', 'bounced', 'completed')),
    scheduled_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_outreach_lead ON outreach_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_outreach_deal ON outreach_log(deal_id);
CREATE INDEX IF NOT EXISTS idx_outreach_agent ON outreach_log(agent_id);
CREATE INDEX IF NOT EXISTS idx_outreach_type ON outreach_log(activity_type);
CREATE INDEX IF NOT EXISTS idx_outreach_channel ON outreach_log(channel);
CREATE INDEX IF NOT EXISTS idx_outreach_created ON outreach_log(created_at DESC);

-- =====================================================
-- TABLE: campaigns — Marketing campaign tracking
-- Feature #154
-- =====================================================
CREATE TABLE IF NOT EXISTS campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(500) NOT NULL,
    type VARCHAR(50) NOT NULL
        CHECK (type IN ('paid_media', 'email_sequence', 'content', 'social', 'event', 'referral')),
    platform VARCHAR(100),
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'active', 'paused', 'completed', 'archived')),
    budget DECIMAL(12,2) DEFAULT 0,
    spend DECIMAL(12,2) DEFAULT 0,
    impressions INTEGER DEFAULT 0,
    clicks INTEGER DEFAULT 0,
    conversions INTEGER DEFAULT 0,
    revenue DECIMAL(12,2) DEFAULT 0,
    roi DECIMAL(8,4) DEFAULT 0,
    start_date DATE,
    end_date DATE,
    assigned_agent VARCHAR(100) REFERENCES agents(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_campaigns_type ON campaigns(type);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaigns_roi ON campaigns(roi DESC);
CREATE INDEX IF NOT EXISTS idx_campaigns_assigned ON campaigns(assigned_agent);

CREATE TRIGGER campaigns_updated_at BEFORE UPDATE ON campaigns
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: suppliers — E-commerce procurement
-- Feature #155
-- =====================================================
CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(500) NOT NULL,
    contact_name VARCHAR(500),
    contact_email VARCHAR(500),
    contact_phone VARCHAR(100),
    website VARCHAR(500),
    country VARCHAR(100),
    moq INTEGER DEFAULT 1,
    lead_time_days INTEGER DEFAULT 14,
    payment_terms VARCHAR(100) DEFAULT 'Net 30',
    currency VARCHAR(3) DEFAULT 'USD',
    rating_quality INTEGER DEFAULT 3 CHECK (rating_quality >= 1 AND rating_quality <= 5),
    rating_price INTEGER DEFAULT 3 CHECK (rating_price >= 1 AND rating_price <= 5),
    rating_reliability INTEGER DEFAULT 3 CHECK (rating_reliability >= 1 AND rating_reliability <= 5),
    status VARCHAR(50) DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'pending_review', 'blacklisted')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_suppliers_status ON suppliers(status);
CREATE INDEX IF NOT EXISTS idx_suppliers_country ON suppliers(country);
CREATE INDEX IF NOT EXISTS idx_suppliers_quality ON suppliers(rating_quality DESC);

CREATE TRIGGER suppliers_updated_at BEFORE UPDATE ON suppliers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: products — Inventory management
-- Feature #156
-- =====================================================
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sku VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(500) NOT NULL,
    description TEXT,
    supplier_id UUID REFERENCES suppliers(id),
    supplier_ref VARCHAR(200),
    category VARCHAR(100),
    unit_cost DECIMAL(12,2) NOT NULL DEFAULT 0,
    landed_cost DECIMAL(12,2) DEFAULT 0,
    retail_price DECIMAL(12,2) NOT NULL DEFAULT 0,
    margin_pct DECIMAL(6,2) DEFAULT 0,
    stock_quantity INTEGER DEFAULT 0,
    reorder_point INTEGER DEFAULT 10,
    reorder_quantity INTEGER DEFAULT 100,
    status VARCHAR(50) DEFAULT 'active'
        CHECK (status IN ('active', 'discontinued', 'out_of_stock', 'draft')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_supplier ON products(supplier_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_status ON products(status);
CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock_quantity) WHERE stock_quantity <= 10;

CREATE TRIGGER products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: revenue — Aggregate revenue tracking by vertical
-- Feature #157
-- =====================================================
CREATE TABLE IF NOT EXISTS revenue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vertical VARCHAR(50) NOT NULL
        CHECK (vertical IN ('trading', 'ecommerce', 'lead_gen', 'funding', 'cre', 'consulting', 'other')),
    period_type VARCHAR(20) NOT NULL
        CHECK (period_type IN ('daily', 'weekly', 'monthly', 'quarterly', 'annual')),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    gross_revenue DECIMAL(15,2) NOT NULL DEFAULT 0,
    costs DECIMAL(15,2) DEFAULT 0,
    net_revenue DECIMAL(15,2) GENERATED ALWAYS AS (gross_revenue - costs) STORED,
    currency VARCHAR(3) DEFAULT 'USD',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(vertical, period_type, period_start)
);

CREATE INDEX IF NOT EXISTS idx_revenue_vertical ON revenue(vertical);
CREATE INDEX IF NOT EXISTS idx_revenue_period ON revenue(period_type, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_revenue_gross ON revenue(gross_revenue DESC);

CREATE TRIGGER revenue_updated_at BEFORE UPDATE ON revenue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: trading_positions — Portfolio tracking
-- Feature #158
-- =====================================================
CREATE TABLE IF NOT EXISTS trading_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL CHECK (side IN ('long', 'short')),
    quantity DECIMAL(20,8) NOT NULL,
    entry_price DECIMAL(20,8) NOT NULL,
    current_price DECIMAL(20,8),
    stop_loss DECIMAL(20,8),
    take_profit DECIMAL(20,8),
    pnl DECIMAL(20,2) DEFAULT 0,
    pnl_pct DECIMAL(10,4) DEFAULT 0,
    platform VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'closed', 'pending', 'cancelled')),
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    journal TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_positions_symbol ON trading_positions(symbol);
CREATE INDEX IF NOT EXISTS idx_positions_status ON trading_positions(status);
CREATE INDEX IF NOT EXISTS idx_positions_platform ON trading_positions(platform);
CREATE INDEX IF NOT EXISTS idx_positions_pnl ON trading_positions(pnl DESC);
CREATE INDEX IF NOT EXISTS idx_positions_opened ON trading_positions(opened_at DESC);

CREATE TRIGGER trading_positions_updated_at BEFORE UPDATE ON trading_positions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: competitors — Competitive intelligence
-- Feature #159
-- =====================================================
CREATE TABLE IF NOT EXISTS competitors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(500) NOT NULL,
    slug VARCHAR(200) UNIQUE NOT NULL,
    verticals TEXT[] NOT NULL DEFAULT '{}',
    priority VARCHAR(20) NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('high', 'medium', 'low')),
    urls JSONB DEFAULT '{}'::jsonb,
    description TEXT,
    strengths TEXT[],
    weaknesses TEXT[],
    active BOOLEAN DEFAULT true,
    last_analyzed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_competitors_slug ON competitors(slug);
CREATE INDEX IF NOT EXISTS idx_competitors_priority ON competitors(priority);
CREATE INDEX IF NOT EXISTS idx_competitors_verticals ON competitors USING GIN(verticals);
CREATE INDEX IF NOT EXISTS idx_competitors_active ON competitors(active) WHERE active = true;

CREATE TRIGGER competitors_updated_at BEFORE UPDATE ON competitors
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: competitor_changes — AI-analyzed change detection
-- Feature #160
-- =====================================================
CREATE TABLE IF NOT EXISTS competitor_changes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    competitor_id UUID NOT NULL REFERENCES competitors(id) ON DELETE CASCADE,
    change_type VARCHAR(50) NOT NULL
        CHECK (change_type IN ('pricing', 'product', 'strategic', 'content', 'hiring', 'partnership')),
    significance_score INTEGER NOT NULL DEFAULT 5
        CHECK (significance_score >= 1 AND significance_score <= 10),
    summary TEXT NOT NULL,
    detail TEXT,
    impact TEXT,
    recommended_action TEXT,
    alert_sent BOOLEAN DEFAULT false,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    analyzed_by VARCHAR(100) REFERENCES agents(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_comp_changes_competitor ON competitor_changes(competitor_id);
CREATE INDEX IF NOT EXISTS idx_comp_changes_type ON competitor_changes(change_type);
CREATE INDEX IF NOT EXISTS idx_comp_changes_significance ON competitor_changes(significance_score DESC);
CREATE INDEX IF NOT EXISTS idx_comp_changes_alert ON competitor_changes(alert_sent) WHERE alert_sent = false;
CREATE INDEX IF NOT EXISTS idx_comp_changes_detected ON competitor_changes(detected_at DESC);

-- =====================================================
-- TABLE: scan_history — Prospecting scan tracking
-- Feature #161
-- =====================================================
CREATE TABLE IF NOT EXISTS scan_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id VARCHAR(100) NOT NULL REFERENCES agents(id),
    source VARCHAR(100) NOT NULL,
    query TEXT NOT NULL,
    result_count INTEGER DEFAULT 0,
    new_prospects INTEGER DEFAULT 0,
    duration_ms INTEGER,
    status VARCHAR(50) DEFAULT 'completed'
        CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    error_message TEXT,
    scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_scan_history_agent ON scan_history(agent_id);
CREATE INDEX IF NOT EXISTS idx_scan_history_source ON scan_history(source);
CREATE INDEX IF NOT EXISTS idx_scan_history_scanned ON scan_history(scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_scan_history_status ON scan_history(status);
