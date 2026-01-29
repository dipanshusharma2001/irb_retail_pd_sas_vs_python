# IRB Retail PD Modelling — SAS vs Python Learning Material

## Overview

This repository provides **learning and reference material** for developing **IRB-compliant retail Probability of Default (PD) models**, using a **mortgage-style retail portfolio** as the primary example.

The key objective is to offer a **side-by-side comparison of commonly used SAS procedures and their Python equivalents**, focusing only on techniques and steps that are **relevant for IRB credit risk modelling**.

The material is intended to support teams transitioning from **SAS-based retail risk modelling** to **Python-based workflows**, while maintaining regulatory alignment and good modelling practices.

---

## Target Audience

- Credit risk model developers familiar with **SAS**
- Risk analysts transitioning to **Python**
- Model validation and governance teams
- Consultants and practitioners working on **IRB retail portfolios** (mortgage, credit card, consumer lending)

This repository assumes familiarity with:
- Logistic regression–based PD models
- IRB modelling concepts
- Model validation and monitoring metrics

---

## Portfolio and Dataset

### Portfolio Type
- Retail mortgage–style PD model (loan-level data)
- 12-month default horizon
- Behavioural and application variables

### Dataset Used
- **LendingClub loan-level data** (publicly available)

The LendingClub dataset is used as a **proxy retail portfolio** for learning purposes.  
It closely resembles retail lending data structures and is well-suited for demonstrating:
- Retail default definitions
- Stability analysis
- Model performance and monitoring metrics

> **Disclaimer:**  
> This dataset is used strictly for educational and internal reference purposes.  
> It does **not** represent any client data or production model.
- The dataset can be downloaded from: https://www.kaggle.com/datasets/wordsforthewise/lending-club


---

## Modelling Philosophy

This material follows **classical IRB retail modelling principles**:

- Logistic regression–based PD models
- WoE-binned predictors
- Emphasis on:
  - Model stability
  - Population representativeness
  - Long-run calibration
- Avoidance of black-box machine learning techniques

Retail-specific nuances (vs wholesale IRB) are explicitly highlighted, including:
- Automated, data-driven modelling
- Absence of expert overrides
- Long-run average default rate–based calibration
- Strong focus on stability and monitoring statistics

---

## Repository Structure

This repository is organized as follows:

### Notebooks
- **01_data_preparation_and_eda.ipynb**: Data ingestion, exploratory data analysis (EDA), and basic portfolio checks.
- **02_feature_engineering_binning_woe.ipynb**: Feature engineering, binning, and Weight of Evidence (WOE) transformations.
- **03_pd_model_development.ipynb**: Development of Probability of Default (PD) models using logistic regression.
- **04_model_validation_and_calibration.ipynb**: Model validation, calibration, and performance assessment.

### Folders
- **data/**: Contains raw and processed datasets.
  - `raw/`: Raw input data.
  - `processed/`: Processed datasets used for modelling.
- **summaries_and_charts/**: Stores generated plots, summaries, and visualizations.

### Source Code Updates
- **src/**: Contains Python scripts for various tasks.
  - `utility_functions.py`: Helper Functions for the project.
  - `config.py`: Configuration settings for the project.

---

## Important Notes

- This repository is not intended for production deployment
- It is a learning and reference artifact
- All modelling choices are simplified for clarity while remaining IRB-aligned

## Author

This project is maintained by **Dipanshu Sharma**.

- **LinkedIn**: [Dipanshu Sharma](https://www.linkedin.com/in/dipanshu-sharma-523921176/)
- **Email**: dipanshusharma.iitb@gmail.com
- **Contact**: +91 9892894009

