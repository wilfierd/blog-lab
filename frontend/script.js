const API = "http://localhost:8080";

let currentUser = null;
let currentTab = 'published';
let editingPostId = null;
let quill = null;
let allPosts = [];

// Initialize Quill Editor if the element exists
document.addEventListener("DOMContentLoaded", () => {
  const editorElem = document.getElementById('editor');
  if (editorElem) {
    quill = new Quill('#editor', {
      theme: 'snow',
      placeholder: 'Share your thoughts...'
    });
  }
});

// Handle authentication & User info on load
if (window.location.pathname.endsWith("blog.html") || window.location.pathname === "/") {
  fetch(`${API}/auth/me`, { credentials: "include" })
    .then(r => {
      if (!r.ok) {
        window.location.href = "index.html";
        return null;
      }
      return r.json();
    })
    .then(user => {
      if (!user) return;
      currentUser = user;

      document.getElementById("username").textContent = user.name || "User";
      if (user.avatar) {
        document.getElementById("avatar").src = user.avatar;
      }

      // Role UI logic
      const role = user.role || "user";
      const badge = document.getElementById("role-badge");
      badge.textContent = role;
      badge.style.display = "inline-block";

      if (role === "admin") {
        badge.style.background = "#ef4444";
        document.getElementById("admin-panel").style.display = "block";
      } else if (role === "dev") {
        badge.style.background = "#8b5cf6";
        document.getElementById("admin-panel").style.display = "block";
      } else {
        badge.style.background = "#10b981";
      }

      loadPosts();
    })
    .catch(err => {
      console.error("Auth error:", err);
      window.location.href = "index.html";
    });
}

function switchTab(tab, element) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  element.classList.add('active');
  currentTab = tab;
  loadPosts();
}

async function previewImage(input) {
  const file = input.files[0];
  if (!file) return;

  const formData = new FormData();
  formData.append('file', file);

  try {
    const res = await fetch(`${API}/api/upload`, {
      method: 'POST',
      credentials: 'include',
      body: formData
    });

    if (res.ok) {
      const data = await res.json();
      document.getElementById('image-url').value = data.url;
      const preview = document.getElementById('upload-preview');
      preview.src = data.url;
      preview.style.display = 'block';
    } else {
      alert('Image upload failed');
    }
  } catch (e) {
    console.error('Upload error', e);
  }
}

// Fetch and display posts
async function loadPosts() {
  try {
    let endpoint = `${API}/api/posts`;
    if (currentTab === 'draft') endpoint = `${API}/api/posts/drafts`;

    const res = await fetch(endpoint, { credentials: "include" });
    let posts = await res.json();
    if (!posts) posts = [];
    allPosts = posts;

    if (currentTab === 'my_posts') {
      posts = posts.filter(p => currentUser && String(p.author_id) === String(currentUser.id));
    }

    const container = document.getElementById("posts");

    if (!posts || posts.length === 0) {
      container.innerHTML = `<div class="empty-state">No posts found in this category.</div>`;
      return;
    }

    const defaultAvatar = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%23e5e7eb'%3E%3Ccircle cx='12' cy='12' r='12'/%3E%3Cpath d='M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z' fill='%239ca3af'/%3E%3C/svg%3E";

    // Check if user has permission to modify this post
    const canModify = (p) => {
      if (!currentUser) return false;
      return currentUser.role === 'admin' || currentUser.role === 'dev' || currentUser.id === p.author_id;
    };

    container.innerHTML = posts.map(p => {
      const safeTitle = escapeHTML(p.title);

      const actionBtns = canModify(p) ? `
        <div class="post-actions" style="margin-left: auto;">
          <button class="btn-icon" onclick="editPost('${p.id || p.ID}')" title="Edit Post">
            <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg>
          </button>
          <button class="btn-icon danger" onclick="deletePost('${p.id || p.ID}')" title="Delete Post">
            <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>
          </button>
        </div>
      ` : '';

      const draftBadge = p.status === 'draft' ? `<span class="draft-badge">Draft</span>` : '';
      const imageHTML = p.cover_image_url ? `<img src="${p.cover_image_url}" class="post-image" alt="Cover Image">` : '';
      const timeStr = p.created_at ? new Date(p.created_at).toLocaleString() : 'Just now';

      return `
        <article class="post-card">
          <div class="post-header" style="align-items: center;">
            <div class="post-meta" style="margin-bottom: 0;">
              <img src="${p.avatar || defaultAvatar}" alt="${p.author}">
              <span class="post-author">${escapeHTML(p.author)}</span>
              <span>·</span>
              <span>${timeStr}</span>
              ${draftBadge}
            </div>
            ${actionBtns}
          </div>
          <h2>${safeTitle}</h2>
          ${imageHTML}
          <div class="post-content ql-editor" style="padding: 0;">${p.content}</div>
        </article>
      `;
    }).join("");
  } catch (err) {
    console.error("Error loading posts:", err);
    document.getElementById("posts").innerHTML = `<div class="empty-state">Failed to load posts. Please try again later.</div>`;
  }
}

async function submitPost(status) {
  const titleInput = document.getElementById("title");
  const title = titleInput.value.trim();
  const content = quill.root.innerHTML;
  const rawText = quill.getText().trim();
  const imageUrl = document.getElementById("image-url").value;

  if (!title || !rawText) {
    alert("Please enter both title and content.");
    return;
  }

  const payload = { title, content, status };
  if (imageUrl) payload.cover_image_url = imageUrl;

  const isEditing = !!editingPostId;
  const url = isEditing ? `${API}/api/posts/${editingPostId}` : `${API}/api/posts`;
  const method = isEditing ? "PUT" : "POST";

  try {
    const res = await fetch(url, {
      method: method,
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (res.ok) {
      cancelEdit();
      loadPosts();
    } else {
      alert("Failed to save post.");
    }
  } catch (err) {
    console.error("Error saving post:", err);
    alert("An error occurred while saving.");
  }
}

function editPost(id) {
  const post = allPosts.find(p => String(p.id || p.ID) === String(id));
  if (!post) return;

  editingPostId = id;
  document.getElementById('form-title').textContent = "Edit Post";
  document.getElementById('title').value = post.title;
  quill.root.innerHTML = post.content || '';

  if (post.cover_image_url) {
    document.getElementById('image-url').value = post.cover_image_url;
    document.getElementById('upload-preview').src = post.cover_image_url;
    document.getElementById('upload-preview').style.display = 'block';
  } else {
    document.getElementById('image-url').value = '';
    document.getElementById('upload-preview').style.display = 'none';
  }

  document.getElementById('cancel-edit').style.display = 'inline-block';
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function cancelEdit() {
  editingPostId = null;
  document.getElementById('form-title').textContent = "Create a new post";
  document.getElementById('title').value = "";
  quill.setContents([]);
  document.getElementById('image-url').value = "";
  document.getElementById('upload-preview').style.display = 'none';
  document.getElementById('image-file').value = "";
  document.getElementById('cancel-edit').style.display = 'none';
}

async function deletePost(postId) {
  if (!postId || postId === 'undefined') {
    alert("Cannot delete post: ID is missing.");
    return;
  }

  if (!confirm("Are you sure you want to delete this post? This action cannot be undone.")) return;

  try {
    const res = await fetch(`${API}/api/posts/${postId}`, {
      method: "DELETE",
      credentials: "include"
    });

    if (res.ok) {
      loadPosts();
    } else {
      alert("Failed to delete post. You might not have the correct permissions.");
    }
  } catch (err) {
    console.error("Error deleting post:", err);
    alert("An error occurred while deleting.");
  }
}

async function logout() {
  try {
    await fetch(`${API}/auth/logout`, { credentials: "include" });
  } catch (e) {
    console.error(e);
  }
  window.location.href = "index.html";
}

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

// --- Profile Modal Logic ---
async function uploadProfileImage(input) {
  const file = input.files[0];
  if (!file) return;

  const formData = new FormData();
  formData.append('file', file);

  try {
    const res = await fetch(`${API}/api/upload`, {
      method: 'POST',
      credentials: 'include',
      body: formData
    });

    if (res.ok) {
      const data = await res.json();
      document.getElementById('profile-avatar-url').value = data.url;
      document.getElementById('profile-avatar-preview').src = data.url;
    } else {
      alert('Avatar upload failed');
    }
  } catch (e) {
    console.error('Upload error', e);
  }
}

function openProfileModal() {
  if (!currentUser) return;
  document.getElementById('profile-name').value = currentUser.name || '';

  const defaultAvatar = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%23e5e7eb'%3E%3Ccircle cx='12' cy='12' r='12'/%3E%3Cpath d='M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z' fill='%239ca3af'/%3E%3C/svg%3E";
  let avatarSrc = currentUser.avatar || defaultAvatar;

  document.getElementById('profile-avatar-preview').src = avatarSrc;
  document.getElementById('profile-avatar-url').value = currentUser.avatar || '';
  document.getElementById('profile-avatar-file').value = '';
  document.getElementById('profile-password').value = '';

  document.getElementById('profile-modal').classList.add('active');
}

function closeProfileModal() {
  document.getElementById('profile-modal').classList.remove('active');
}

const profModal = document.getElementById('profile-modal');
if (profModal) {
  profModal.addEventListener("click", (e) => {
    if (e.target === profModal) closeProfileModal();
  });
}

async function saveProfile() {
  const name = document.getElementById('profile-name').value.trim();
  const avatar = document.getElementById('profile-avatar-url').value.trim();
  const password = document.getElementById('profile-password').value;

  if (!name) {
    alert("Name is required.");
    return;
  }

  const payload = { name, avatar };
  if (password) payload.password = password;

  const btn = document.getElementById('save-profile-btn');
  btn.disabled = true;
  btn.textContent = 'Saving...';

  try {
    const res = await fetch(`${API}/api/me`, {
      method: "PUT",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (res.ok) {
      alert("Profile updated successfully!");
      closeProfileModal();
      window.location.reload();
    } else {
      const txt = await res.text();
      alert("Failed to update profile: " + txt);
    }
  } catch (err) {
    console.error("Error updating profile:", err);
    alert("An error occurred while saving profile.");
  } finally {
    btn.disabled = false;
    btn.textContent = 'Save Profile';
  }
}
