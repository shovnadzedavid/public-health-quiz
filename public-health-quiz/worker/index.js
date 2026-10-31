export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // CORS უსაფრთხოების წესები ბრაუზერიდან წვდომისთვის
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    // OPTIONS (Preflight) მოთხოვნის დამუშავება ბრაუზერისთვის
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // ახალი მარშრუტი: URL-ის დამატება RAG ბაზაში
    if (request.method === 'POST' && url.pathname === '/api/add-url') {
      try {
        const { targetUrl } = await request.json();

        // 1. ვკითხულობთ მითითებულ ვებგვერდს
        const siteResponse = await fetch(targetUrl, { headers: { 'User-Agent': 'Mozilla/5.0' } });
        if (!siteResponse.ok) throw new Error("ვერ მოხერხდა მითითებული ვებგვერდის გახსნა.");
        const html = await siteResponse.text();
        
        // 2. ვასუფთავებთ ტექსტს HTML ტეგებისგან და ვიღებთ სატესტო ბლოკს (1000 სიმბოლო)
        const cleanText = html.replace(/<[^>]*>?/gm, ' ').replace(/\s+/g, ' ').trim();
        const chunk = cleanText.substring(0, 1000); 

        // 3. ტექსტს ვაქცევთ ვექტორად Gemini API-ს მეშვეობით
        const geminiRes = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${env.GEMINI_API_KEY}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              model: "models/text-embedding-004",
              content: { parts: [{ text: chunk }] }
            })
          }
        );
        const geminiData = await geminiRes.json();
        
        if (!geminiData.embedding) {
            throw new Error("Gemini-მ ვერ დააგენერირა ვექტორი. შეამოწმე API გასაღები.");
        }
        const vector = geminiData.embedding.values;

        // 4. ვინახავთ ინფორმაციას Supabase-ის medical_documents ცხრილში
        const supabaseRes = await fetch(`${env.SUPABASE_URL}/rest/v1/medical_documents`, {
          method: 'POST',
          headers: {
            'apikey': env.SUPABASE_KEY,
            'Authorization': `Bearer ${env.SUPABASE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
          },
          body: JSON.stringify({
            content: chunk,
            metadata: { source: targetUrl, type: "webpage" },
            embedding: vector
          })
        });

        if (!supabaseRes.ok) {
            const errText = await supabaseRes.text();
            throw new Error(`Supabase Error: ${errText}`);
        }

        // წარმატებული პასუხის დაბრუნება ფრონტენდზე
        return new Response(JSON.stringify({ success: true, message: "წყარო წარმატებით დაემატა ბაზას" }), { 
          status: 200,
          headers: { 'Content-Type': 'application/json', ...corsHeaders } 
        });
      } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), { 
            status: 500, 
            headers: { 'Content-Type': 'application/json', ...corsHeaders } 
        });
      }
    }

    // შენი არსებული ქუიზის ბექენდ ლოგიკა (თუ გაქვს სხვა endpoint-ები) უნდა ჩაისვას აქ.
    // ...

    return new Response("მარშრუტი არ მოიძებნა", { status: 404, headers: corsHeaders });
  },
};
