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

```text
irb-retail-sas-vs-python/
│
├── README.md
│
├── data/
│   ├── raw/            # Original LendingClub dataset
│   └── processed/      # Model-ready datasets
│
├── notebooks/
│   ├── 00_retail_irb_orientation.ipynb
│   ├── 01_lendingclub_data_setup.ipynb
│   ├── 02_data_cleaning.ipynb
│   ├── 03_binning_woe_iv.ipynb
│   ├── 04_pd_model_logistic.ipynb
│   ├── 05_validation_metrics.ipynb
│   ├── 06_calibration.ipynb
│   └── 07_stability_monitoring.ipynb
│
├── src/
│   ├── data_utils.py
│   ├── woe_utils.py
│   ├── metrics.py
│   ├── calibration.py
│   └── stability.py
│
├── figures/
│   └── Saved plots for reporting and PPT use
│
├── requirements.txt
└── .gitignore
```

---

## Important Notes

- This repository is not intended for production deployment
- It is a learning and reference artifact
- All modelling choices are simplified for clarity while remaining IRB-aligned
