import sys 
import os 
import re
import typing 
import math
import datetime
import pickle
import joblib
from joblib import Parallel, delayed
from itertools import combinations, permutations, product

import warnings
warnings.filterwarnings("ignore")

# Core libraries
import numpy as np
import pandas as pd

# Statistics & modelling
import scipy.stats as stats
import statsmodels.api as sm
import statsmodels.formula.api as smf
from sklearn.isotonic import IsotonicRegression
from sklearn.metrics import roc_auc_score, roc_curve, confusion_matrix, classification_report
from statsmodels.stats.outliers_influence import variance_inflation_factor



# Metrics
from sklearn.metrics import roc_auc_score, roc_curve

# Visualization
import matplotlib.pyplot as plt
import seaborn as sns

# main_directory
main_dir = "/Users/sharmadipanshu/Developer/KPMG/irb_retail_pd_sas_vs_python/"

# Display options
pd.set_option("display.max_columns", 200)
pd.set_option("display.float_format", "{:.4f}".format)

# Plot style
sns.set_style("whitegrid")
plt.rcParams["figure.figsize"] = (10, 6)
