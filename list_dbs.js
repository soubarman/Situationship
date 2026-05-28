const { GoogleAuth } = require('google-auth-library');

async function listDatabases() {
  try {
    const auth = new GoogleAuth({
      keyFile: './serviceAccountKey.json',
      scopes: ['https://www.googleapis.com/auth/cloud-platform']
    });
    
    const client = await auth.getClient();
    const projectId = await auth.getProjectId();
    
    const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases`;
    const response = await client.request({ url });
    
    console.log(JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.error("Error:", err.message);
  }
}

listDatabases();
