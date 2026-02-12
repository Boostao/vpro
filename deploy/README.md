# VPRO 2.0 Deployment & Evaluation Guide

This guide is intended for reviewers and administrators to quickly stand up the VPRO 2.0 environment for evaluation.

## 🚀 Quick Start (Docker)

To evaluate the application in a clean, isolated environment, use Docker Compose. This will start the Shiny application and an optional PostgreSQL database for cloud feature demonstrations.

1. **Prerequisites**: Ensure you have [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) installed.
2. **Setup environment**:
   ```bash
   cp .env.example .env
   ```
3. **Launch the stack**:
   ```bash
   docker compose -f docker-compose.deploy.yml up -d
   ```
4. **Access the app**: Open your browser to [http://localhost:3838](http://localhost:3838).

---

## 🖱️ Demo Click Path

Follow these steps to explore the core functionality of VPRO 2.0:

1. **Discovery**: Click the **BEC Map Explorer** tab. Explore the interactive map; filter by BEC Zone or Species (e.g., 'Abies lasiocarpa') to see plot locations.
2. **Project Selection**: Use the sidebar to select **Project**: `hju`. Choosing a project will populate the Plot selector.
3. **Data Entry (Veg)**: 
   - Navigate to the **Vegetation** tab.
   - Select any plot from the dropdown. 
   - Modify a cover value in one of the layers (A, B, C, or D). 
   - Note the instant save behavior and data validation feedback.
4. **Data Entry (Site/Env)**:
   - Navigate to the **Site/Env** tab.
   - Review the General, Mensuration, and Soil sub-tabs.
   - Experiment with the **Coordinate Tools** to see DMS ↔ DD conversion in action.
5. **Reporting**:
   - Go to the **Reporting** tab.
   - Select the **Short Veg** report from the template list.
   - Click **Generate Report**.
   - Review the PDF/HTML output rendered via Quarto, maintaining parity with the original Access reports.

---

## 🛠️ Troubleshooting

### DuckDB Database Locks
DuckDB is a single-writer database. If you receive an error about "database is locked":
- Ensure no other R sessions or CLI tools are holding a write lock on the `.duckdb` files in the `data/` directory.
- In the Docker deployment, the `data/` directory is mounted as Read-Only by default for safety. If you need to enable saves in the container, modify the volume mount in `docker-compose.deploy.yml` by removing the `:ro` suffix.

### Port Conflicts
If port `3838` is already in use by another application:
- Modify the `ports` mapping in `docker-compose.deploy.yml` (e.g., `"8080:3838"`) and restart the stack.

### PostgreSQL Connection
If the Sync or Auth modules show connection errors:
- Ensure the `db` service is healthy (`docker compose ps`).
- Check your `.env` file credentials match the defaults in `docker-compose.deploy.yml`.

---

## 📞 Support
For technical issues or feedback during review, please refer to the [CLIENT_REVIEW_SCOPE.md](CLIENT_REVIEW_SCOPE.md) document or contact the development team.
