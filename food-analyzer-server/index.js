import express from "express";
import cors from "cors";
import fetch from "node-fetch";

const app = express();
app.use(cors());
app.use(express.json());

app.post("/food/analyze-text", async (req, res) => {
  try {
    const { text, locale = "ar-SA" } = req.body || {};
    if (!text || !text.trim()) {
      return res.status(400).json({ error: "Missing text" });
    }

    const prompt = `
You are a nutrition analyst. Locale: ${locale}.
Given a free-text meal description, estimate *reasonable* nutrition. Output strictly valid JSON in this schema:
{
  "item": string,
  "calories_kcal": number,
  "macros": { "protein_g": number, "carbs_g": number, "fat_g": number },
  "fiber_g": number,
  "sugar_g": number,
  "sodium_mg": number,
  "confidence": number,
  "notes": string
}
If user says "وجبة ماك تشيكن", infer a typical fast-food meal (sandwich + fries + soda) unless the text clearly says sandwich only.
No prose. JSON only.

User input: """${text}"""
`;

    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${process.env.OPENAI_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.1,
        messages: [
          { role: "system", content: "You output JSON only. No extra text." },
          { role: "user", content: prompt }
        ]
      })
    });

    const data = await r.json();
    const raw = data?.choices?.[0]?.message?.content?.trim() || "{}";
    const parsed = JSON.parse(raw); // تأكد أنه JSON صالح
    res.json(parsed);
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`Food analyzer running on :${PORT}`));
