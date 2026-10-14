const list = document.getElementById("items");
const error = document.getElementById("error");

fetch("/api/items")
  .then((response) => {
    if (!response.ok) {
      throw new Error("API ответил " + response.status);
    }
    return response.json();
  })
  .then((items) => {
    items.forEach((item) => {
      const li = document.createElement("li");
      li.textContent = item.id + ". " + item.name;
      list.appendChild(li);
    });
  })
  .catch((err) => {
    error.hidden = false;
    error.textContent = err.message;
  });
