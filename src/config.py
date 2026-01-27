import sys 
import os 
import re
import typing 
import math
import datetime
import pickle
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
