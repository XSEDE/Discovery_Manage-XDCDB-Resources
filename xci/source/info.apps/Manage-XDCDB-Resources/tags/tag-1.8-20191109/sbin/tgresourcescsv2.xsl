<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                version="1.0">
    <xsl:output method="text"/>

    <xsl:template match="/">
        <xsl:text>ResourceID,ResourceName,SiteID,ResourceKits,OrganizationAbbrev,OrganizationName,AmieName,PopsName,TgcdbResourceName,ResourceCode,ResourceDescription,Timestamp&#xa;</xsl:text>
        <xsl:apply-templates select=".//V4tgcdbRP/TgcdbOrganization"/>
    </xsl:template> 

    <xsl:template match="TgcdbOrganization">
        <xsl:for-each select="TgcdbResource">
            <xsl:sort select="../SiteID"/>
            <xsl:sort select="ResourceID"/>
<xsl:value-of select="ResourceID"/>,"<xsl:value-of select="ResourceName"/>",<xsl:value-of select="../SiteID"/>,<xsl:value-of select="ResourceKits"/>,"<xsl:value-of select="../organization_abbrev"/>","<xsl:value-of select="../organization_name"/>","<xsl:value-of select="../amie_name"/>","<xsl:value-of select="pops_name"/>","<xsl:value-of select="resource_name"/>",<xsl:value-of select="resource_code"/>,"<xsl:value-of select="resource_description"/>","<xsl:value-of select="../../@Timestamp"/>"<xsl:text>&#xa;</xsl:text>
        </xsl:for-each>
    </xsl:template>

</xsl:stylesheet>
