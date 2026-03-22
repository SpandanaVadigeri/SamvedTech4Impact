const bcrypt = require('bcryptjs');
const fs = require('fs');

async function initDB() {
    console.log("Generating Default Users in database.json");

    const salt = await bcrypt.genSalt(10);
    const adminHash = await bcrypt.hash('admin123', salt);
    const supHash = await bcrypt.hash('sup123', salt);
    const workerHash = await bcrypt.hash('worker123', salt);

    const db = {
      users: [
        {
          id: "u1",
          username: "admin",
          password_hash: adminHash,
          role: "admin",
          created_at: new Date().toISOString()
        },
        {
          id: "u2",
          username: "supervisor",
          password_hash: supHash,
          role: "supervisor",
          created_at: new Date().toISOString()
        },
        {
          id: "u3",
          username: "worker",
          password_hash: workerHash,
          role: "worker",
          created_at: new Date().toISOString()
        }
      ]
    };

    fs.writeFileSync('database.json', JSON.stringify(db, null, 2));
    console.log("Successfully created default users!");
}

initDB();
