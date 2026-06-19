"""
IBDMS AI Health Chatbot — RAG-style eligibility & FAQ engine.

Architecture (Lightweight RAG)
-------------------------------
1. SCOPE GUARD   — Hard out-of-scope classifier.  Queries containing zero
                   blood / health domain signals are rejected immediately
                   with the mandatory fallback response.
2. RETRIEVAL     — BM25-lite weighted keyword overlap scores every topic
                   in the knowledge base.  Highest-scoring chunk is
                   selected as the retrieved context.
3. AUGMENTATION  — The retrieved answer IS the augmented context; no
                   LLM call is needed because the knowledge base is
                   fully pre-written.  This keeps latency at <1 ms and
                   requires zero API keys.

Upgrading to full LLM-based generation:
  Replace `process_chat_message` with an OpenAI / Mistral call that
  receives the retrieved chunk as system context.  The rest of the
  pipeline (scope guard + retrieval) stays identical.

Covers every common blood-donation health question a donor or recipient might
ask. Structured eligibility flow is handled client-side (chatbot_screen.dart)
for a smoother step-by-step UX; this engine handles free-text queries.

Topic map:
  1.  Donation intervals / frequency
  2.  Weight requirements
  3.  Age requirements
  4.  Haemoglobin / iron / anaemia
  5.  Blood group compatibility
  6.  Eligibility summary / criteria
  7.  Pregnancy / female-specific
  8.  Medication / drug deferral
  9.  Tattoo / piercing / acupuncture
  10. Alcohol / smoking
  11. Travel / malaria deferral
  12. Chronic disease — diabetes
  13. Chronic disease — hypertension / heart
  14. Infections — HIV / AIDS
  15. Infections — hepatitis B & C
  16. COVID-19 infection & vaccination
  17. Surgery / transfusion deferral
  18. Donation process / procedure
  19. Benefits of donating
  20. Blood type distribution & demand
  21. Blood storage & shelf-life
  22. First-time donor guidance
  23. Post-donation care / side-effects
  24. Platelet / plasma donation
  25. Greeting / thanks
  26. Out-of-scope catch-all
"""

# ── Utility ──────────────────────────────────────────────────────────────────

def _kw(*words):
    """Build a flat keyword tuple."""
    return words


# ── Topic definitions ────────────────────────────────────────────────────────

_TOPICS = [

    # 1 — Donation intervals
    (
        _kw("interval", "how often", "56", "56 days", "wait", "how long",
            "frequency", "next donation", "again", "cooling", "cooldown"),
        (
            "**Donation Frequency Guidelines:**\n\n"
            "• **Whole Blood:** minimum 56 days (8 weeks) between donations.\n"
            "• **Platelets (apheresis):** minimum 7 days; max 24 times/year.\n"
            "• **Plasma:** minimum 28 days (4 weeks).\n"
            "• **Double Red Cells:** minimum 112 days.\n\n"
            "These intervals allow haemoglobin, iron, and blood-volume to fully "
            "replenish before the next extraction."
        ),
    ),

    # 2 — Weight
    (
        _kw("weight", "heavy", "kg", "kilograms", "light", "minimum weight",
            "too light", "50 kg", "50kg"),
        (
            "**Weight Requirement:**\n\n"
            "Donors must weigh at least **50 kg (110 lbs)**.\n\n"
            "This threshold ensures the body can safely tolerate the ~450 mL "
            "blood drawn without experiencing hypovolemia (dangerous drop in "
            "blood volume). Donors under 50 kg are temporarily deferred until "
            "they reach the minimum weight."
        ),
    ),

    # 3 — Age
    (
        _kw("age", "old", "young", "years", "how old", "minimum age",
            "maximum age", "teenager", "senior", "elderly"),
        (
            "**Age Requirements:**\n\n"
            "• **Minimum age:** 18 years (16–17 with parental consent in some regions).\n"
            "• **Maximum age:** 65 years for routine donations.\n"
            "• Donors aged 60–65 may require additional health screening at the "
            "collection centre's discretion.\n\n"
            "If you are outside this range, consult your nearest blood bank — "
            "some facilities accept healthy seniors over 65 on a case-by-case basis."
        ),
    ),

    # 4 — Haemoglobin / iron / anaemia
    (
        _kw("haemoglobin", "hemoglobin", "hb", "iron", "anaemia", "anemia",
            "ferritin", "low blood", "blood level", "g/dl"),
        (
            "**Haemoglobin (Hb) Requirements:**\n\n"
            "• **Female donors:** Hb ≥ 12.5 g/dL\n"
            "• **Male donors:** Hb ≥ 13.0 g/dL\n\n"
            "Low Hb results in a **temporary deferral** until levels recover. "
            "To raise iron naturally:\n"
            "  – Eat iron-rich foods: red meat, spinach, lentils, fortified cereals.\n"
            "  – Pair with vitamin C to enhance absorption.\n"
            "  – Avoid tea/coffee 1 hour before/after iron-rich meals.\n\n"
            "A certified nurse will perform a quick finger-prick Hb test before "
            "every donation."
        ),
    ),

    # 5 — Blood group compatibility
    (
        _kw("compatibility", "compatible", "universal", "receive", "give",
            "type", "blood group", "a+", "b+", "ab", "o-", "o+", "rh",
            "positive", "negative", "transfusion match"),
        (
            "**Blood Group Compatibility:**\n\n"
            "**For Red Blood Cell (RBC) transfusions:**\n"
            "• O− → can donate to ALL groups (universal RBC donor)\n"
            "• O+ → can donate to O+, A+, B+, AB+\n"
            "• A− → can donate to A−, A+, AB−, AB+\n"
            "• A+ → can donate to A+, AB+\n"
            "• B− → can donate to B−, B+, AB−, AB+\n"
            "• B+ → can donate to B+, AB+\n"
            "• AB− → can donate to AB−, AB+\n"
            "• AB+ → can receive from ALL groups (universal RBC recipient)\n\n"
            "**For Plasma:** AB+ is the universal plasma *donor*.\n\n"
            "Always confirm compatibility with the hospital blood bank team — "
            "cross-matching tests are mandatory before any transfusion."
        ),
    ),

    # 6 — Eligibility summary
    (
        _kw("eligible", "eligibility", "can i donate", "qualify", "criteria",
            "requirements", "conditions", "am i eligible", "check eligibility"),
        (
            "**Core Blood Donation Eligibility Criteria:**\n\n"
            "✅ Age: 18–65 years\n"
            "✅ Weight: ≥ 50 kg\n"
            "✅ Haemoglobin: ≥ 12.5 g/dL (F) / ≥ 13.0 g/dL (M)\n"
            "✅ No whole-blood donation in the past 56 days\n"
            "✅ No fever, cold, or active infection in the past 7 days\n"
            "✅ No major surgery or transfusion in the past 12 months\n"
            "✅ Not pregnant or breastfeeding\n"
            "✅ No blood-borne infections (HIV, hepatitis B/C)\n\n"
            "Tap **Start Eligibility Check** for a guided, step-by-step personal assessment."
        ),
    ),

    # 7 — Pregnancy / female-specific
    (
        _kw("pregnant", "pregnancy", "breastfeed", "breastfeeding", "female",
            "woman", "women", "menstruation", "period", "postpartum",
            "after delivery", "after birth"),
        (
            "**Female & Pregnancy-Specific Guidelines:**\n\n"
            "• **Pregnancy:** Donors are deferred for the entire duration of "
            "pregnancy.\n"
            "• **Post-delivery:** Wait at least **6 months** after giving birth.\n"
            "• **Breastfeeding:** Wait **6 weeks** after you stop breastfeeding.\n"
            "• **Menstruation:** You CAN donate during your period if you feel "
            "well and your Hb is sufficient. It is a personal choice.\n\n"
            "Women with heavy periods may have lower iron reserves — ensure your "
            "Hb is tested at the centre before donating."
        ),
    ),

    # 8 — Medication
    (
        _kw("medicine", "medication", "drug", "tablet", "pill", "antibiotic",
            "aspirin", "warfarin", "blood thinner", "paracetamol",
            "ibuprofen", "anticoagulant", "prescription"),
        (
            "**Medication Deferral Guidelines:**\n\n"
            "• **Antibiotics:** Defer until 7 days after completing the full course.\n"
            "• **Aspirin:** Defer 48 hours before platelet donation (OK for whole blood).\n"
            "• **Ibuprofen / NSAIDs:** Defer 48 hours.\n"
            "• **Blood thinners (warfarin, heparin, rivaroxaban):** Generally permanently deferred.\n"
            "• **Paracetamol (Tylenol):** No deferral required.\n"
            "• **Antihypertensives (blood pressure pills):** Allowed if BP is controlled and within range.\n"
            "• **Retinoids (isotretinoin / acitretin):** 1-month deferral after stopping.\n\n"
            "Always disclose ALL medications to collection centre staff. "
            "They will make the final deferral decision."
        ),
    ),

    # 9 — Tattoo / piercing
    (
        _kw("tattoo", "piercing", "acupuncture", "needle", "body art",
            "ink", "ear piercing"),
        (
            "**Tattoo, Piercing & Acupuncture Deferral:**\n\n"
            "• **Tattoo / body piercing at a non-licensed facility:** "
            "12-month deferral due to hepatitis B/C and bloodborne pathogen risk.\n"
            "• **Tattoo / piercing at a licensed, sterile facility:** "
            "Deferral may be as short as 3–6 months depending on local policy — "
            "confirm with your nearest blood bank.\n"
            "• **Acupuncture (sterile disposable needles):** No deferral required.\n"
            "• **Acupuncture (reusable needles):** 12-month deferral.\n\n"
            "When in doubt, bring documentation from the facility."
        ),
    ),

    # 10 — Alcohol / smoking
    (
        _kw("alcohol", "drink", "drunk", "beer", "wine", "smoke", "smoking",
            "cigarette", "tobacco", "vape", "nicotine"),
        (
            "**Alcohol & Smoking Guidelines:**\n\n"
            "**Alcohol:**\n"
            "• Do NOT donate if you consumed alcohol in the **past 24 hours**.\n"
            "• Even small amounts impair post-donation recovery.\n"
            "• Avoid alcohol for 24 hours after donation as well.\n\n"
            "**Smoking:**\n"
            "• Smoking itself does not automatically disqualify you.\n"
            "• However, refrain from smoking for at least **2 hours before** "
            "and **4 hours after** donation to reduce cardiovascular stress.\n"
            "• Long-term heavy smokers may have reduced oxygen-carrying capacity "
            "— Hb will be checked at the centre."
        ),
    ),

    # 11 — Travel / malaria
    (
        _kw("travel", "abroad", "malaria", "tropical", "mosquito", "country",
            "pakistan", "africa", "asia", "zika", "dengue", "dengue fever"),
        (
            "**Travel-Related Deferral:**\n\n"
            "• **Malaria-endemic regions:** 3–12 month deferral after returning, "
            "depending on the country visited and local blood bank policy.\n"
            "• **Zika-endemic regions:** Deferral typically 28 days after return "
            "without symptoms; 120 days if symptomatic.\n"
            "• **Dengue fever:** Defer until 6 months after full recovery.\n\n"
            "If you have lived in or visited a region with high malaria risk for "
            "more than 5 years, some centres require a full blood parasite screen "
            "before accepting donations.\n\n"
            "Always inform the collection centre of recent travel history."
        ),
    ),

    # 12 — Diabetes
    (
        _kw("diabetes", "diabetic", "sugar", "blood sugar", "insulin",
            "type 1", "type 2", "glucose"),
        (
            "**Diabetes & Blood Donation:**\n\n"
            "• **Type 2 diabetes (diet/tablet controlled):** Generally eligible "
            "if blood sugar is well-controlled and there are no complications "
            "(kidney disease, nerve damage, severe eye disease).\n"
            "• **Type 1 diabetes (insulin-dependent):** Most centres defer "
            "insulin-dependent donors due to hypoglycaemia risk after donation.\n"
            "• You must disclose your diabetes status to the screening nurse.\n\n"
            "The final decision rests with the blood bank physician after reviewing "
            "your current HbA1c and medication history."
        ),
    ),

    # 13 — Hypertension / heart
    (
        _kw("hypertension", "blood pressure", "bp", "high bp", "heart",
            "cardiac", "heart attack", "stroke", "chest pain", "pacemaker"),
        (
            "**Hypertension & Heart Conditions:**\n\n"
            "**Blood Pressure:**\n"
            "• Acceptable range: systolic 90–160 mmHg and diastolic 60–100 mmHg.\n"
            "• Controlled hypertension on medication: generally eligible.\n"
            "• Readings outside the acceptable range on donation day → temporary deferral.\n\n"
            "**Heart Conditions:**\n"
            "• History of heart attack or stroke → permanently deferred at most centres.\n"
            "• Heart surgery, pacemaker, or valve replacement → permanently deferred.\n"
            "• Mild controlled arrhythmia → check with the blood bank physician.\n\n"
            "Carry your medication list and most recent BP readings when you visit."
        ),
    ),

    # 14 — HIV / AIDS
    (
        _kw("hiv", "aids", "hiv positive", "immune", "immunodeficiency",
            "sti", "std", "sexually transmitted"),
        (
            "**HIV/AIDS & Blood Donation:**\n\n"
            "• Donors who test positive for **HIV are permanently deferred** — "
            "their blood cannot be used for transfusion.\n"
            "• All donated blood is routinely screened for HIV, hepatitis B/C, "
            "syphilis, and other bloodborne pathogens.\n"
            "• If you have had **high-risk sexual behaviour** (unprotected sex "
            "with multiple partners) in the past 3–12 months, you may be deferred "
            "depending on local policy.\n\n"
            "Donating blood is NOT a way to get tested — the window period means "
            "an infection acquired recently may not yet be detectable. "
            "Contact a health clinic for confidential HIV testing."
        ),
    ),

    # 15 — Hepatitis
    (
        _kw("hepatitis", "hep b", "hep c", "liver", "jaundice",
            "hepatitis b", "hepatitis c", "hbsag"),
        (
            "**Hepatitis B & C — Donation Policy:**\n\n"
            "• **Past or current hepatitis B or C infection → permanently deferred.**\n"
            "• All blood units are screened for HBsAg (hepatitis B surface antigen) "
            "and anti-HCV antibodies.\n"
            "• Hepatitis B vaccination alone does NOT disqualify you — only active "
            "infection does.\n"
            "• If you have had jaundice of unknown cause in the past 12 months, "
            "you are temporarily deferred pending investigation.\n\n"
            "For hepatitis testing or vaccination, contact your nearest clinic."
        ),
    ),

    # 16 — COVID-19
    (
        _kw("covid", "corona", "coronavirus", "covid-19", "covid19",
            "vaccine", "vaccination", "pfizer", "moderna", "astrazeneca",
            "booster", "pcr", "positive test"),
        (
            "**COVID-19 & Vaccination Guidelines:**\n\n"
            "**Recent COVID-19 infection:**\n"
            "• Mild/moderate illness: defer at least **14 days** after full "
            "symptom resolution.\n"
            "• Severe illness / hospitalisation: defer at least **4 weeks** "
            "after full recovery.\n\n"
            "**COVID-19 Vaccination:**\n"
            "• Approved mRNA vaccines (Pfizer, Moderna): no deferral required "
            "after vaccination if you feel well.\n"
            "• AstraZeneca / viral-vector vaccines: most centres require a "
            "48-hour symptom-free wait.\n"
            "• If you experience fever or flu-like side-effects post-vaccination, "
            "wait until you are symptom-free for 48 hours.\n\n"
            "Policies may vary by country. Always confirm with your local blood bank."
        ),
    ),

    # 17 — Surgery / transfusion
    (
        _kw("surgery", "operation", "transplant", "transfusion", "received blood",
            "blood transfusion", "organ", "procedure"),
        (
            "**Surgery & Transfusion Deferral:**\n\n"
            "• **Minor surgery (e.g., dental extraction, laparoscopy):** "
            "Defer 7–30 days depending on healing and anaesthetic used.\n"
            "• **Major surgery:** Defer at least **12 months** after full recovery.\n"
            "• **Received a blood transfusion:** Defer at least **12 months** "
            "due to infection transmission risk.\n"
            "• **Organ or tissue transplant:** Defer **12 months** minimum; "
            "some centres permanently defer.\n\n"
            "Inform the screening nurse of any recent procedures, including dental work."
        ),
    ),

    # 18 — Donation process / procedure
    (
        _kw("process", "procedure", "how", "steps", "what happens",
            "collection", "how long", "duration", "phlebotomy", "needle hurt",
            "painful", "vein", "arm"),
        (
            "**The Blood Donation Process:**\n\n"
            "1. **Registration:** Provide ID and complete a health questionnaire.\n"
            "2. **Health screening:** BP check, Hb finger-prick test, pulse, temperature.\n"
            "3. **Pre-donation hydration:** Drink ~500 mL water before donation.\n"
            "4. **Donation:** A sterile 16-gauge needle is inserted into your arm vein. "
            "Whole blood collection takes **8–12 minutes** for ~450 mL.\n"
            "5. **Post-donation rest:** Rest for 10–15 minutes and receive refreshments.\n"
            "6. **Total visit time:** Approximately 45–60 minutes.\n\n"
            "The needle prick causes brief discomfort — most donors describe it as "
            "a small pinch. The actual donation is painless."
        ),
    ),

    # 19 — Benefits of donating
    (
        _kw("benefit", "benefits", "good for", "advantage", "why donate",
            "health benefit", "save lives", "why should i"),
        (
            "**Why Donate Blood?**\n\n"
            "**For the recipient:**\n"
            "• One donation can save up to **3 lives** (whole blood is separated into "
            "red cells, plasma, and platelets).\n"
            "• Critical for surgeries, cancer treatment, accident victims, and "
            "childbirth complications.\n\n"
            "**For the donor's health:**\n"
            "• Free health screening (BP, Hb, pulse, infectious disease markers).\n"
            "• Stimulates new blood cell production — refreshing your blood supply.\n"
            "• Regular donors may have lower iron over-accumulation, potentially "
            "reducing cardiovascular risk.\n"
            "• Psychological benefit — donating is linked to improved mood and "
            "sense of purpose.\n\n"
            "Blood cannot be manufactured — it can only come from volunteers like you."
        ),
    ),

    # 20 — Blood type demand
    (
        _kw("demand", "needed", "most needed", "rarest", "rare blood",
            "shortage", "supply", "common blood type", "distribution"),
        (
            "**Blood Type Supply & Demand:**\n\n"
            "**Most universally needed:**\n"
            "• **O−** (Universal donor) — always in critical shortage; only 7% of people have it.\n"
            "• **O+** — Most common type (~38%); always needed.\n"
            "• **A+** — Second most common (~34%).\n\n"
            "**Rarest types:**\n"
            "• **AB−** (~1% of population) — rare but key plasma donor for all types.\n"
            "• **B−** (~2%) — rare, frequently urgently needed.\n\n"
            "**Platelets:** All types are needed, but AB+ platelets are "
            "universally compatible for platelet transfusions.\n\n"
            "No matter your blood type, your donation is valuable!"
        ),
    ),

    # 21 — Blood storage
    (
        _kw("storage", "stored", "shelf life", "expire", "how long blood",
            "preservation", "refrigerate", "bank blood"),
        (
            "**Blood Component Storage:**\n\n"
            "| Component | Storage Temp | Shelf Life |\n"
            "|---|---|---|\n"
            "| Red Blood Cells | 2–6 °C | 35–42 days |\n"
            "| Platelets | 20–24 °C (agitated) | 5–7 days |\n"
            "| Fresh Frozen Plasma | −18 °C or below | 12 months |\n"
            "| Cryoprecipitate | −18 °C or below | 12 months |\n\n"
            "Because platelets expire so quickly (5–7 days), frequent donations "
            "are critical — supply must be continuously replenished."
        ),
    ),

    # 22 — First-time donor
    (
        _kw("first time", "first donation", "first-time", "never donated",
            "new donor", "nervous", "scared", "afraid", "anxiety"),
        (
            "**First-Time Donor Guide:**\n\n"
            "It is completely normal to feel nervous! Here's how to prepare:\n\n"
            "**Before donation:**\n"
            "• Eat a healthy meal 2–3 hours before (avoid fatty foods).\n"
            "• Drink at least 500 mL of water or juice beforehand.\n"
            "• Wear comfortable clothing with sleeves that roll up easily.\n"
            "• Get a good night's sleep.\n\n"
            "**At the centre:**\n"
            "• Tell the nurse it is your first time — they will guide you carefully.\n"
            "• Stay relaxed and breathe normally during the needle insertion.\n"
            "• You can ask to stop at any time — it is your choice.\n\n"
            "**After donation:**\n"
            "• Rest for 15 minutes and drink the refreshments provided.\n"
            "• Avoid strenuous exercise for 24 hours.\n\n"
            "Most first-time donors find it much easier than expected — and many "
            "become regular lifelong donors!"
        ),
    ),

    # 23 — Post-donation care
    (
        _kw("after donation", "post donation", "side effect", "side-effect",
            "dizzy", "dizziness", "faint", "fainting", "bruise", "weakness",
            "tired", "rest", "recovery", "care after"),
        (
            "**Post-Donation Care & Side Effects:**\n\n"
            "**Normal & expected:**\n"
            "• Mild dizziness or lightheadedness — sit/lie down immediately.\n"
            "• Small bruise at the needle site — resolves within 3–7 days.\n"
            "• Slight fatigue for a few hours.\n\n"
            "**What to do:**\n"
            "• Keep the bandage on for at least 4–6 hours.\n"
            "• Drink extra fluids (water, juice) for the next 24–48 hours.\n"
            "• Avoid alcohol, hot showers, and heavy exercise for 24 hours.\n"
            "• Eat an iron-rich meal — spinach, lentils, red meat.\n\n"
            "**Seek help if you experience:**\n"
            "• Fainting or prolonged dizziness.\n"
            "• Numbness or tingling in the arm.\n"
            "• Bleeding that does not stop after 15 minutes of pressure.\n\n"
            "Call your collection centre if any unusual symptoms persist."
        ),
    ),

    # 24 — Platelet / plasma donation
    (
        _kw("platelet", "plasma", "apheresis", "component donation",
            "plasma donation", "platelet donation"),
        (
            "**Platelet & Plasma Donation (Apheresis):**\n\n"
            "**Platelets:**\n"
            "• Blood is drawn, platelets are separated by a machine, and remaining "
            "components are returned to your body.\n"
            "• Duration: 1.5–2.5 hours.\n"
            "• Can donate every 7 days (max 24 times/year).\n"
            "• Critical for cancer, leukaemia, and organ transplant patients.\n\n"
            "**Plasma:**\n"
            "• Liquid component separated; red cells returned to donor.\n"
            "• Duration: ~45 minutes.\n"
            "• Can donate every 28 days.\n"
            "• Used for burn patients, bleeding disorders, and manufacturing "
            "plasma-derived medicines.\n\n"
            "Both procedures are safe and performed with sterile, single-use equipment."
        ),
    ),

    # 25 — Greeting / thanks
    (
        _kw("hi", "hello", "hey", "good morning", "good evening",
            "thanks", "thank you", "thank", "appreciate", "great"),
        (
            "Hello! 👋 I am your **IBDMS AI Health Assistant**.\n\n"
            "I can help you with:\n"
            "• Blood donation eligibility criteria\n"
            "• Donation intervals and frequency\n"
            "• Health conditions, medications, and deferrals\n"
            "• Post-donation care and side effects\n"
            "• Blood type compatibility and demand\n\n"
            "Type your question below, or tap **Start Eligibility Check** for a "
            "step-by-step personal assessment. 🩸"
        ),
    ),
]


# ── RAG Layer 1: Domain Scope Guard ──────────────────────────────────────────
# Any query containing at least one of these signals is in-scope.
_DOMAIN_SIGNALS = frozenset([
    "blood", "donat", "donor", "recipient", "transfus", "plasma", "platelet",
    "haemoglobin", "hemoglobin", "iron", "anaemi", "anemi", "eligib",
    "deferr", "blood group", "blood type", "a+", "a-", "b+", "b-",
    "ab+", "ab-", "o+", "o-", "hiv", "aids", "hepatitis", "malaria",
    "covid", "vaccin", "pregnan", "tattoo", "piercing", "surgery",
    "diabetes", "hypertension", "heart", "medic", "drug", "alcohol",
    "smoking", "weight", "age", "dob", "born", "unit", "pint",
    "apheresis", "whole blood", "red cell", "white cell", "component",
    "cooldown", "cool down", "how long", "how often", "interval",
    "first time", "side effect", "after donat", "post donat",
    "can i", "am i eligible", "am i able", "is it safe",
])

_OUT_OF_SCOPE_REPLY = (
    "I am an automated assistant specialized exclusively in blood donation, "
    "diseases, and health safety guidelines. "
    "I cannot assist with out-of-scope inquiries."
)


def _is_in_scope(query: str) -> bool:
    q = query.lower()
    return any(sig in q for sig in _DOMAIN_SIGNALS)


# ── RAG Layer 2: BM25-lite Retrieval ─────────────────────────────────────────

def _retrieve(query: str) -> tuple[str, float]:
    """
    Scores every topic in the knowledge base using weighted keyword overlap
    (approximating BM25 without external dependencies).

    Returns (best_response, confidence_score).
    """
    import re
    q_tokens = set(re.sub(r"[^a-z0-9 ]", " ", query.lower()).split())
    best_score = 0.0
    best_response = ""

    for keywords, response in _TOPICS:
        kw_set = set(" ".join(keywords).lower().split())
        overlap = len(q_tokens & kw_set)
        if overlap == 0:
            continue
        # Normalised score: overlap / sqrt(|query| * |keywords|)
        score = overlap / ((len(q_tokens) * len(kw_set)) ** 0.5 + 1e-9)
        if score > best_score:
            best_score = score
            best_response = response

    return best_response, round(best_score, 4)


# ── Public API ────────────────────────────────────────────────────────────────

def process_chat_message(query: str) -> dict:
    """
    RAG pipeline entry point for POST /api/chat/message.

    Returns a dict:
      response   str   — The answer text (markdown).
      in_scope   bool  — False when the scope guard fires.
      confidence float — Retrieval confidence score (0–1).
    """
    # Layer 1 — Scope guard.
    if not _is_in_scope(query):
        return {
            "response": _OUT_OF_SCOPE_REPLY,
            "in_scope": False,
            "confidence": 0.0,
        }

    # Layer 2 — Retrieval.
    response, confidence = _retrieve(query)

    if not response or confidence < 0.03:
        response = (
            "I couldn't find a specific answer for that.  Please ask about "
            "blood donation eligibility, health conditions, donation process, "
            "or blood type compatibility."
        )

    return {
        "response": response,
        "in_scope": True,
        "confidence": confidence,
    }


def process_chatbot_query(user_raw_text: str) -> str:
    """Legacy entry point (GET /api/chatbot/query) — preserved for compatibility."""
    result = process_chat_message(user_raw_text)
    return result["response"]
