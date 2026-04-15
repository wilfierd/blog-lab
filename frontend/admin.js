const API = "";

let currentUser = null;

// Auth check and role verify
document.addEventListener("DOMContentLoaded", () => {
  fetch(`${API}/auth/me`, { credentials: "include" })
    .then(r => {
      if (!r.ok) { window.location.href = "index.html"; return null; }
      return r.json();
    })
    .then(user => {
      if (!user) return;
      currentUser = user;
      if (user.role !== 'admin' && user.role !== 'dev') {
        alert("Access Denied: You do not have permission to view this page.");
        window.location.href = "blog.html";
        return;
      }
      loadUsers();
    })
    .catch(err => {
      console.error("Auth check failed:", err);
      window.location.href = "blog.html";
    });
});

// Load Users
async function loadUsers() {
  try {
    const res = await fetch(`${API}/api/admin/users`, { credentials: "include" });
    if (!res.ok) throw new Error("Failed to fetch users");
    const users = await res.json();
    
    const tbody = document.getElementById("users-table-body");
    if (!users || users.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align: center; color: #6b7280; padding: 2rem;">No users found.</td></tr>`;
      return;
    }

    tbody.innerHTML = users.map(u => `
      <tr>
        <td style="color: #6b7280; font-size: 0.85rem;">#${u.id || u.ID}</td>
        <td style="font-weight: 500;">${escapeHTML(u.username)}</td>
        <td>
          <div>${escapeHTML(u.name)}</div>
          <div style="font-size: 0.8rem; color: #6b7280;">${escapeHTML(u.email || '-')}</div>
        </td>
        <td>
          <span class="role-badge role-${(u.role || 'user').toLowerCase()}">${u.role || 'user'}</span>
        </td>
        <td style="font-size: 0.85rem; color: #6b7280;">
          ${u.last_access ? new Date(u.last_access).toLocaleString() : 'Never'}
        </td>
        <td>
          <div class="action-btns" style="justify-content: flex-end;">
            <button class="btn btn-outline" style="padding: 0.35rem 0.75rem; font-size: 0.8rem;" 
              onclick="editUser('${u.id || u.ID}', '${escapeHTML(u.username)}', '${escapeHTML(u.name)}', '${escapeHTML(u.email)}', '${u.role}')">
              Edit
            </button>
            <button class="btn ${u.id === currentUser.id ? 'btn-outline' : 'btn-danger'}" 
              style="padding: 0.35rem 0.75rem; font-size: 0.8rem;" 
              ${u.id === currentUser.id ? 'disabled title="Cannot delete yourself"' : ''}
              onclick="deleteUser('${u.id || u.ID}')">
              Delete
            </button>
          </div>
        </td>
      </tr>
    `).join("");
  } catch (err) {
    console.error("Error loading users:", err);
    alert("Failed to load user list.");
  }
}

// Modal Handling
const modal = document.getElementById("user-modal");

function openUserModal() {
  document.getElementById("modal-title").textContent = "Create New User";
  document.getElementById("user-id").value = "";
  document.getElementById("username").value = "";
  document.getElementById("username").disabled = false;
  document.getElementById("name").value = "";
  document.getElementById("email").value = "";
  document.getElementById("password").value = "";
  document.getElementById("role").value = "user";
  document.getElementById("pwd-hint").textContent = "(Required)";
  
  modal.classList.add("active");
}

function editUser(id, username, name, email, role) {
  document.getElementById("modal-title").textContent = "Edit User";
  document.getElementById("user-id").value = id;
  document.getElementById("username").value = username;
  document.getElementById("username").disabled = true; // Cannot edit username usually
  document.getElementById("name").value = name;
  document.getElementById("email").value = email === '-' ? '' : email;
  document.getElementById("password").value = "";
  document.getElementById("role").value = role || "user";
  document.getElementById("pwd-hint").textContent = "(Leave blank to keep unchanged)";
  
  modal.classList.add("active");
}

function closeUserModal() {
  modal.classList.remove("active");
}

// Save (Create or Update)
async function saveUser() {
  const id = document.getElementById("user-id").value;
  const username = document.getElementById("username").value.trim();
  const name = document.getElementById("name").value.trim();
  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;
  const role = document.getElementById("role").value;

  const isUpdate = !!id;

  if (!username || !name) {
    alert("Username and Name are required.");
    return;
  }
  if (!isUpdate && !password) {
    alert("Password is required for new users.");
    return;
  }

  const payload = { name, email, role };
  if (!isUpdate) payload.username = username;
  if (password) payload.password = password;

  const btn = document.getElementById("save-user-btn");
  btn.disabled = true;
  btn.textContent = "Saving...";

  try {
    const url = isUpdate ? `${API}/api/admin/users/${id}` : `${API}/api/admin/users`;
    const method = isUpdate ? "PUT" : "POST";

    const res = await fetch(url, {
      method: method,
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (res.ok) {
      closeUserModal();
      loadUsers();
    } else {
      const txt = await res.text();
      alert(`Failed to save user. ${txt}`);
    }
  } catch (err) {
    console.error("Error saving user:", err);
    alert("An error occurred while saving the user.");
  } finally {
    btn.disabled = false;
    btn.textContent = "Save User";
  }
}

// Delete User
async function deleteUser(id) {
  if (id === String(currentUser.id)) {
    alert("You cannot delete your own account.");
    return;
  }
  
  if (!confirm("Are you sure you want to delete this user? ALL THEIR POSTS AND COMMENTS WILL BE DELETED. This cannot be undone.")) return;

  try {
    const res = await fetch(`${API}/api/admin/users/${id}`, {
      method: "DELETE",
      credentials: "include"
    });

    if (res.ok) {
      loadUsers();
    } else {
      const txt = await res.text();
      alert(`Failed to delete user. ${txt}`);
    }
  } catch (err) {
    console.error("Error deleting user:", err);
    alert("An error occurred while deleting the user.");
  }
}

// Close modal when clicking outside
modal.addEventListener("click", (e) => {
  if (e.target === modal) closeUserModal();
});

// Utility
function escapeHTML(str) {
  if (!str) return "";
  return String(str).replace(/[&<>'"]/g, 
    tag => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;'
    }[tag])
  );
}
